/****************************************************************************
 *
 * Custom build (Buoyant Aero): preload a deployment site for the 3D view.
 *
 ****************************************************************************/

#include "Viewer3DSitePreloader.h"
#include "Viewer3DTileReply.h"
#include "SettingsManager.h"
#include "AppSettings.h"
#include "FlightMapSettings.h"
#include "QGCMapUrlEngine.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QDateTime>
#include <QtCore/QRegularExpression>
#include <QtCore/QStandardPaths>
#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtCore/QDebug>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <cmath>

// Mirror of the constants in Viewer3DTileQuery.cc so the preload fetches the
// same zoom level the 3D viewer will ask for.
static constexpr double kPi                 = 3.14159265358979323846;
static constexpr int    kMaxTileCounts      = 200;
static constexpr int    kMaxZoomLevel       = 23;
static constexpr int    kExtraZoomLevels    = 2;      // also cache Z-1, Z-2 (viewer steps down on missing tiles)
static constexpr int    kWatchdogMs         = 90000;  // give up on tiles if nothing arrives for this long
static constexpr double kMaxRadiusMeters    = 5000;
static constexpr double kMinRadiusMeters    = 100;

static const char* kOverpassServers[] = {
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
};

Viewer3DSitePreloader::Viewer3DSitePreloader(QObject *parent)
    : QObject{parent}
{
    _networkManager = new QNetworkAccessManager(this);
    _networkManager->setTransferTimeout(180000);
    _watchdog = new QTimer(this);
    _watchdog->setSingleShot(true);
    connect(_watchdog, &QTimer::timeout, this, &Viewer3DSitePreloader::_tileWatchdog);
    refreshSites();
}

Viewer3DSitePreloader::~Viewer3DSitePreloader()
{
    cancel();
}

QString Viewer3DSitePreloader::mapsDirectory() const
{
    QString dir;
    AppSettings* appSettings = SettingsManager::instance()->appSettings();
    if (appSettings) {
        dir = appSettings->viewer3DMapsSavePath();
    }
    if (dir.isEmpty()) {
        dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/Maps3D");
    }
    QDir().mkpath(dir);
    return dir;
}

QString Viewer3DSitePreloader::_sanitize(const QString &name)
{
    QString out = name.trimmed();
    out.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_\\-]+")), QStringLiteral("_"));
    out = out.left(48);
    if (out.isEmpty()) {
        out = QStringLiteral("site");
    }
    return out;
}

QString Viewer3DSitePreloader::defaultSiteName() const
{
    return QStringLiteral("site-") + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmm"));
}

QString Viewer3DSitePreloader::sitePath(const QString &siteName) const
{
    return QDir(mapsDirectory()).filePath(_sanitize(siteName) + QStringLiteral(".osm"));
}

QString Viewer3DSitePreloader::siteNameFromPath(const QString &path) const
{
    if (path.isEmpty() || !path.endsWith(QStringLiteral(".osm"), Qt::CaseInsensitive)) {
        return QString();
    }
    return QFileInfo(path).completeBaseName();
}

void Viewer3DSitePreloader::refreshSites()
{
    QDir dir(mapsDirectory());
    QStringList sites;
    const QFileInfoList entries = dir.entryInfoList(QStringList() << QStringLiteral("*.osm"), QDir::Files, QDir::Name);
    for (const QFileInfo &fi : entries) {
        sites.append(fi.completeBaseName());
    }
    if (sites != _availableSites) {
        _availableSites = sites;
        emit availableSitesChanged();
    }
}

bool Viewer3DSitePreloader::deleteSite(const QString &siteName)
{
    const bool ok = QFile::remove(sitePath(siteName));
    refreshSites();
    return ok;
}

void Viewer3DSitePreloader::_setBusy(bool busy)
{
    if (_busy != busy) {
        _busy = busy;
        emit busyChanged();
    }
}

void Viewer3DSitePreloader::_setStatus(const QString &status)
{
    if (_status != status) {
        _status = status;
        emit statusChanged();
    }
}

void Viewer3DSitePreloader::_setProgress(double progress)
{
    if (!qFuzzyCompare(_progress, progress)) {
        _progress = progress;
        emit progressChanged();
    }
}

void Viewer3DSitePreloader::cancel()
{
    if (!_busy) {
        return;
    }
    _cancelled = true;
    _watchdog->stop();
    if (_osmReply) {
        _osmReply->abort();
    }
    // Tile replies are children of this object; drop them.
    const QList<Viewer3DTileReply*> replies = findChildren<Viewer3DTileReply*>();
    for (Viewer3DTileReply* reply : replies) {
        reply->disconnect(this);
        reply->deleteLater();
    }
    _finish(false, tr("Preload cancelled"));
}

void Viewer3DSitePreloader::_finish(bool ok, const QString &message)
{
    _watchdog->stop();
    _setStatus(message);
    _setProgress(ok ? 100 : _progress);
    _setBusy(false);
    refreshSites();
    emit preloadFinished(ok, ok ? _osmFilePath : QString());
}

void Viewer3DSitePreloader::preload(const QString &siteName, const QGeoCoordinate &center, double radiusMeters)
{
    if (_busy) {
        return;
    }
    if (!center.isValid() || (center.latitude() == 0 && center.longitude() == 0)) {
        _setStatus(tr("No valid position for the site"));
        emit preloadFinished(false, QString());
        return;
    }
    if (std::isnan(radiusMeters) || radiusMeters <= 0) {
        radiusMeters = 1500;
    }
    _radiusMeters = qBound(kMinRadiusMeters, radiusMeters, kMaxRadiusMeters);
    _siteName = _sanitize(siteName.isEmpty() ? defaultSiteName() : siteName);
    _center = center;
    _cancelled = false;
    _overpassAttempt = 0;
    _tilesFailed = 0;

    const double dLat = _radiusMeters / 111320.0;
    const double dLon = _radiusMeters / (111320.0 * std::cos(center.latitude() * kPi / 180.0));
    _bboxMin = QGeoCoordinate(center.latitude() - dLat, center.longitude() - dLon, 0);
    _bboxMax = QGeoCoordinate(center.latitude() + dLat, center.longitude() + dLon, 0);
    _osmFilePath = sitePath(_siteName);

    _setBusy(true);
    _setProgress(0);
    _setStatus(tr("Downloading buildings (%1 m radius)…").arg(qRound(_radiusMeters)));
    _requestOsm(QString::fromLatin1(kOverpassServers[0]));
}

QString Viewer3DSitePreloader::_buildOverpassQuery() const
{
    // bbox order for Overpass global setting: south,west,north,east
    return QStringLiteral(
        "[out:xml][timeout:120][bbox:%1,%2,%3,%4];"
        "(way[\"building\"];way[\"building:part\"];relation[\"building\"];);"
        "(._;>;);"
        "out body;")
        .arg(_bboxMin.latitude(), 0, 'f', 6)
        .arg(_bboxMin.longitude(), 0, 'f', 6)
        .arg(_bboxMax.latitude(), 0, 'f', 6)
        .arg(_bboxMax.longitude(), 0, 'f', 6);
}

void Viewer3DSitePreloader::_requestOsm(const QString &serverUrl)
{
    QNetworkRequest request{QUrl(serverUrl)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("QGroundControl-Buoyant-3DPreload/1.0"));
    const QByteArray body = "data=" + QUrl::toPercentEncoding(_buildOverpassQuery());
    _osmReply = _networkManager->post(request, body);
    connect(_osmReply, &QNetworkReply::finished, this, &Viewer3DSitePreloader::_osmReplyFinished);
}

void Viewer3DSitePreloader::_osmReplyFinished()
{
    QNetworkReply* reply = _osmReply;
    _osmReply = nullptr;
    if (!reply) {
        return;
    }
    reply->deleteLater();
    if (_cancelled) {
        return;
    }

    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QByteArray data = reply->readAll();
    const bool ok = (reply->error() == QNetworkReply::NoError) && statusCode >= 200 && statusCode < 300 && data.contains("<osm");

    if (!ok) {
        _overpassAttempt++;
        const int serverCount = sizeof(kOverpassServers) / sizeof(kOverpassServers[0]);
        if (_overpassAttempt < serverCount) {
            _setStatus(tr("Building server busy, trying mirror…"));
            _requestOsm(QString::fromLatin1(kOverpassServers[_overpassAttempt]));
            return;
        }
        qWarning() << "3D preload: Overpass failed" << statusCode << reply->errorString();
        _finish(false, tr("Building download failed (%1). Check internet and retry.").arg(reply->errorString().isEmpty() ? QString::number(statusCode) : reply->errorString()));
        return;
    }

    if (!_saveOsm(data)) {
        _finish(false, tr("Could not write %1").arg(_osmFilePath));
        return;
    }

    _setProgress(10);
    _setStatus(tr("Buildings saved (%1 KB). Caching satellite tiles…").arg(data.size() / 1024));
    _startTilePrefetch();
}

bool Viewer3DSitePreloader::_saveOsm(QByteArray data)
{
    // The 3D viewer takes its map extent + origin from the <bounds> element.
    // Overpass output may omit it, so make sure it is present and matches our request.
    if (!data.contains("<bounds")) {
        const int osmTag = data.indexOf("<osm");
        int insertAt = (osmTag >= 0) ? data.indexOf('>', osmTag) : -1;
        if (insertAt >= 0) {
            insertAt += 1;
            const QByteArray bounds = QStringLiteral("\n  <bounds minlat=\"%1\" minlon=\"%2\" maxlat=\"%3\" maxlon=\"%4\"/>")
                .arg(_bboxMin.latitude(), 0, 'f', 7)
                .arg(_bboxMin.longitude(), 0, 'f', 7)
                .arg(_bboxMax.latitude(), 0, 'f', 7)
                .arg(_bboxMax.longitude(), 0, 'f', 7).toUtf8();
            data.insert(insertAt, bounds);
        }
    }

    QDir().mkpath(mapsDirectory());
    QFile file(_osmFilePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "3D preload: cannot open" << _osmFilePath << file.errorString();
        return false;
    }
    file.write(data);
    file.close();
    return true;
}

// ---- tile prefetch ---------------------------------------------------------

int Viewer3DSitePreloader::_maxTileCount(int zoomLevel, const QGeoCoordinate &coordinateMin, const QGeoCoordinate &coordinateMax)
{
    // Same heuristic as MapTileQuery::maxTileCount so we land on the same zoom level.
    const double mapSize = std::pow(2.0, zoomLevel);
    const double latResolution = 180.0 / mapSize;
    const double lonResolution = 360.0 / mapSize;
    const double latLen = coordinateMax.latitude() - coordinateMin.latitude();
    const double lonLen = coordinateMax.longitude() - coordinateMin.longitude();
    const int tileXCount = std::ceil(lonLen / lonResolution);
    const int tileYCount = std::ceil(latLen / latResolution);
    return tileXCount * tileYCount;
}

QPoint Viewer3DSitePreloader::_latLonToTileXY(const QGeoCoordinate &coordinate, int zoomLevel)
{
    // Same Web-Mercator pixel math as MapTileQuery::latLonToPixelXY.
    const double maxLatitude = 85.05112878;
    const double latitude  = qBound(-maxLatitude, coordinate.latitude(), maxLatitude);
    const double longitude = qBound(-180.0, coordinate.longitude(), 180.0);
    const double x = (longitude + 180.0) / 360.0;
    const double sinLatitude = std::sin(latitude * kPi / 180.0);
    const double y = 0.5 - std::log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * kPi);
    const double mapSize = std::pow(2.0, zoomLevel) * 256.0;
    const int pixelX = static_cast<int>(qBound(0.0, x * mapSize + 0.5, mapSize - 1));
    const int pixelY = static_cast<int>(qBound(0.0, y * mapSize + 0.5, mapSize - 1));
    return QPoint(pixelX / 256, pixelY / 256);
}

void Viewer3DSitePreloader::_startTilePrefetch()
{
    FlightMapSettings* flightMapSettings = SettingsManager::instance()->flightMapSettings();
    _mapType = flightMapSettings->mapProvider()->rawValue().toString() + QStringLiteral(" ") + flightMapSettings->mapType()->rawValue().toString();
    _mapId = UrlFactory::getQtMapIdFromProviderType(_mapType);

    for (_baseZoom = kMaxZoomLevel; _baseZoom > 0; _baseZoom--) {
        if (_maxTileCount(_baseZoom, _bboxMin, _bboxMax) < kMaxTileCounts) {
            break;
        }
    }

    // Count tiles for all zoom levels up front for progress reporting.
    _tilesTotalAllLevels = 0;
    _tilesDoneAllLevels = 0;
    for (int z = _baseZoom; z > 0 && z > _baseZoom - 1 - kExtraZoomLevels; z--) {
        const QPoint minTile = _latLonToTileXY(QGeoCoordinate(_bboxMax.latitude(), _bboxMin.longitude()), z);
        const QPoint maxTile = _latLonToTileXY(QGeoCoordinate(_bboxMin.latitude(), _bboxMax.longitude()), z);
        _tilesTotalAllLevels += (maxTile.x() - minTile.x() + 1) * (maxTile.y() - minTile.y() + 1);
    }

    _currentZoom = _baseZoom;
    _zoomLevelsRemaining = 1 + kExtraZoomLevels;
    _startZoomLevel();
}

void Viewer3DSitePreloader::_startZoomLevel()
{
    if (_cancelled) {
        return;
    }
    if (_zoomLevelsRemaining <= 0 || _currentZoom <= 0) {
        const QString msg = _tilesFailed
            ? tr("Site \"%1\" ready (%2 tiles could not be fetched, they will load online).").arg(_siteName).arg(_tilesFailed)
            : tr("Site \"%1\" ready for offline 3D view (map: %2, zoom %3).").arg(_siteName, _mapType).arg(_baseZoom);
        _finish(true, msg);
        return;
    }

    const QPoint minTile = _latLonToTileXY(QGeoCoordinate(_bboxMax.latitude(), _bboxMin.longitude()), _currentZoom);
    const QPoint maxTile = _latLonToTileXY(QGeoCoordinate(_bboxMin.latitude(), _bboxMax.longitude()), _currentZoom);

    _tilesTotal = 0;
    _tilesDone = 0;
    for (int x = minTile.x(); x <= maxTile.x(); x++) {
        for (int y = minTile.y(); y <= maxTile.y(); y++) {
            Viewer3DTileReply* reply = new Viewer3DTileReply(_currentZoom, x, y, _mapId, this);
            connect(reply, &Viewer3DTileReply::tileDone,   this, &Viewer3DSitePreloader::_tileFinished);
            connect(reply, &Viewer3DTileReply::tileEmpty,  this, &Viewer3DSitePreloader::_tileFinished);
            connect(reply, &Viewer3DTileReply::tileGiveUp, this, &Viewer3DSitePreloader::_tileFinished);
            _tilesTotal++;
        }
    }
    qDebug() << "3D preload: zoom" << _currentZoom << _tilesTotal << "tiles";
    _watchdog->start(kWatchdogMs);

    if (_tilesTotal == 0) {
        _zoomLevelsRemaining--;
        _currentZoom--;
        _startZoomLevel();
    }
}

void Viewer3DSitePreloader::_tileFinished()
{
    Viewer3DTileReply* reply = qobject_cast<Viewer3DTileReply*>(sender());
    if (reply) {
        reply->disconnect(this);
        reply->deleteLater();
    }
    if (_cancelled) {
        return;
    }
    _tilesDone++;
    _tilesDoneAllLevels++;
    _watchdog->start(kWatchdogMs);

    const double pct = 10.0 + 90.0 * (_tilesTotalAllLevels ? (double)_tilesDoneAllLevels / _tilesTotalAllLevels : 1.0);
    _setProgress(qMin(99.0, pct));
    _setStatus(tr("Caching satellite tiles… %1 / %2").arg(_tilesDoneAllLevels).arg(_tilesTotalAllLevels));

    if (_tilesDone >= _tilesTotal) {
        _zoomLevelsRemaining--;
        _currentZoom--;
        _startZoomLevel();
    }
}

void Viewer3DSitePreloader::_tileWatchdog()
{
    if (!_busy || _cancelled) {
        return;
    }
    // Some tiles never came back. Drop them and move on; the OSM file is already saved.
    const QList<Viewer3DTileReply*> replies = findChildren<Viewer3DTileReply*>();
    _tilesFailed += replies.size();
    for (Viewer3DTileReply* reply : replies) {
        reply->disconnect(this);
        reply->deleteLater();
    }
    _tilesDoneAllLevels += (_tilesTotal - _tilesDone);
    _zoomLevelsRemaining--;
    _currentZoom--;
    _startZoomLevel();
}
