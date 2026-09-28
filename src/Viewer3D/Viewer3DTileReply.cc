/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "Viewer3DTileReply.h"

#include <MapProvider.h>
#include <QGCMapUrlEngine.h>
#include <QGeoTileFetcherQGC.h>
#include <QGeoFileTileCacheQGC.h>
#include <QGCMapEngine.h>
#include <QGCCacheTile.h>

#include <QtCore/QFile>
#include <QtCore/QTimer>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>

QByteArray Viewer3DTileReply::_bingNoTileImage;

Viewer3DTileReply::Viewer3DTileReply(int zoomLevel, int tileX, int tileY, int mapId, QObject *parent)
    : QObject{parent}
{
    if (_bingNoTileImage.length() == 0) {
        QFile file(QStringLiteral(":/res/BingNoTileBytes.dat"));
        if (file.open(QFile::ReadOnly)) {
            _bingNoTileImage = file.readAll();
            file.close();
        } else {
            qWarning() << "Error opening file" << file.fileName();
        }
    }

    _timeoutCounter = 0;
    _timeoutTimer = new QTimer(this);
    _networkManager = new QNetworkAccessManager(this);
    _networkManager->setTransferTimeout(9000);

    _tile.x = tileX;
    _tile.y = tileY;
    _tile.zoomLevel = zoomLevel;
    _tile.mapId = mapId;
    _tile.data.clear();
    _mapId = mapId;
    prepareDownload();

    _timeoutTimer->start(10000);
    connect(_timeoutTimer, &QTimer::timeout, this, &Viewer3DTileReply::timeoutTimerEvent);
}

Viewer3DTileReply::~Viewer3DTileReply()
{
    delete _networkManager;
    delete _timeoutTimer;
}

bool Viewer3DTileReply::_isBingNoTile(const QByteArray &data) const
{
    const SharedMapProvider mapProvider = UrlFactory::getMapProviderFromQtMapId(_tile.mapId);
    return mapProvider && mapProvider->isBingProvider() && data.size() && data == _bingNoTileImage;
}

void Viewer3DTileReply::prepareDownload()
{
    if (!_cacheChecked) {
        // First attempt: ask the QGC tile cache (same DB the 2D map and Offline Maps use).
        _cacheChecked = true;
        const QString providerType = UrlFactory::getProviderTypeFromQtMapId(_mapId);
        QGCFetchTileTask* const task = QGeoFileTileCacheQGC::createFetchTileTask(providerType, _tile.x, _tile.y, _tile.zoomLevel);
        connect(task, &QGCFetchTileTask::tileFetched, this, &Viewer3DTileReply::_cacheTileFetched);
        connect(task, &QGCMapTask::error, this, &Viewer3DTileReply::_cacheTileError);
        getQGCMapEngine()->addTask(task);
        return;
    }
    startNetworkDownload();
}

void Viewer3DTileReply::_cacheTileFetched(QGCCacheTile *tile)
{
    if (tile && !tile->img().isEmpty() && !_isBingNoTile(tile->img())) {
        _tile.data = tile->img();
        delete tile;
        _timeoutTimer->stop();
        disconnect(_timeoutTimer, &QTimer::timeout, this, &Viewer3DTileReply::timeoutTimerEvent);
        emit tileDone(_tile);
        return;
    }
    delete tile;
    startNetworkDownload();
}

void Viewer3DTileReply::_cacheTileError(QGCMapTask::TaskType type, const QString &errorString)
{
    Q_UNUSED(type);
    Q_UNUSED(errorString);
    // Not in cache: go to the network.
    startNetworkDownload();
}

void Viewer3DTileReply::startNetworkDownload()
{
    const QNetworkRequest request = QGeoTileFetcherQGC::getNetworkRequest(_mapId, _tile.x, _tile.y, _tile.zoomLevel);
    _reply = _networkManager->get(request);
    connect(_reply, &QNetworkReply::finished, this, &Viewer3DTileReply::requestFinished);
    connect(_reply, &QNetworkReply::errorOccurred, this, &Viewer3DTileReply::requestError);
}

void Viewer3DTileReply::requestFinished()
{
    const int statusCode = _reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    _tile.data = _reply->readAll();
    const SharedMapProvider mapProvider = UrlFactory::getMapProviderFromQtMapId(_tile.mapId);
    disconnect(_reply, &QNetworkReply::finished, this, &Viewer3DTileReply::requestFinished);
    disconnect(_reply, &QNetworkReply::errorOccurred, this, &Viewer3DTileReply::requestError);

    if (statusCode < 200 || statusCode >= 300) {
        // HTTP error page is not a tile. Leave data empty so the timeout timer retries.
        _tile.data.clear();
        emit tileError(_tile);
        return;
    }

    _timeoutTimer->stop();
    disconnect(_timeoutTimer, &QTimer::timeout, this, &Viewer3DTileReply::timeoutTimerEvent);

    if (_isBingNoTile(_tile.data)) {
        // Bing doesn't return an error if you request a tile above supported zoom level
        // It instead returns an image of a missing tile graphic. We need to detect that
        // and error out so 3D View will deal with zooming correctly even if it doesn't have the tile.
        _tile.data.clear();
        emit tileEmpty(_tile);
        return;
    }

    if (mapProvider && !_tile.data.isEmpty()) {
        const QString format = mapProvider->getImageFormat(_tile.data);
        if (!format.isEmpty()) {
            QGeoFileTileCacheQGC::cacheTile(mapProvider->getMapName(), _tile.x, _tile.y, _tile.zoomLevel, _tile.data, format);
        }
    }
    emit tileDone(_tile);
}

void Viewer3DTileReply::requestError()
{
    emit tileError(_tile);
    if (_reply) {
        disconnect(_reply, &QNetworkReply::finished, this, &Viewer3DTileReply::requestFinished);
        disconnect(_reply, &QNetworkReply::errorOccurred, this, &Viewer3DTileReply::requestError);
    }
}

void Viewer3DTileReply::timeoutTimerEvent()
{
    if(_timeoutCounter > 5){
        if (_reply) {
            disconnect(_reply, &QNetworkReply::finished, this, &Viewer3DTileReply::requestFinished);
            disconnect(_reply, &QNetworkReply::errorOccurred, this, &Viewer3DTileReply::requestError);
        }
        disconnect(_timeoutTimer, &QTimer::timeout, this, &Viewer3DTileReply::timeoutTimerEvent);
        emit tileGiveUp(_tile);
        _timeoutTimer->stop();
    }else if(_tile.data.isEmpty()){
        emit tileError(_tile);
        prepareDownload();
        _timeoutCounter++;
    }
}
