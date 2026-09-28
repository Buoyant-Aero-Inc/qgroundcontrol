/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include <QtCore/QObject>
#include "QGCMapTasks.h"

class QNetworkReply;
class QNetworkAccessManager;
class QTimer;
class QGCCacheTile;

///     @author Omid Esrafilian <esrafilian.omid@gmail.com>
///
///     Custom build: tiles are looked up in the QGC map tile cache first and
///     every tile fetched from the network is written back into that cache, so
///     the 3D view works offline once a site has been preloaded.

class Viewer3DTileReply : public QObject
{
public:

    typedef struct tileInfo_s{
        int x, y, zoomLevel;
        QByteArray data;
        int mapId;
    } tileInfo_t;

    Q_OBJECT
public:
    explicit Viewer3DTileReply(int zoomLevel, int tileX, int tileY, int mapId, QObject *parent = nullptr);
    ~Viewer3DTileReply();

private:

    QNetworkAccessManager* _networkManager;
    QNetworkReply* _reply = nullptr;
    tileInfo_t _tile;
    QTimer* _timeoutTimer;
    int _mapId;
    int _timeoutCounter;
    bool _cacheChecked = false;
    static QByteArray       _bingNoTileImage;

    void prepareDownload();
    void startNetworkDownload();
    void requestFinished();
    void requestError();
    void timeoutTimerEvent();
    void _cacheTileFetched(QGCCacheTile *tile);
    void _cacheTileError(QGCMapTask::TaskType type, const QString &errorString);
    bool _isBingNoTile(const QByteArray &data) const;

signals:
    void tileDone(tileInfo_t);
    void tileEmpty(tileInfo_t);
    void tileError(tileInfo_t);
    void tileGiveUp(tileInfo_t);
};
