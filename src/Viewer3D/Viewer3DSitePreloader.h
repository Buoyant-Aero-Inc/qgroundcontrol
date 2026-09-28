/****************************************************************************
 *
 * Custom build (Buoyant Aero): preload a deployment site for the 3D view.
 *
 * Downloads OpenStreetMap building data around a point from the Overpass API,
 * stores it as an .osm file in the app's Maps3D folder, then fetches the
 * satellite tiles the 3D view will need and writes them into the QGC tile
 * cache. After that the 3D view works with no connectivity.
 *
 ****************************************************************************/

#pragma once

#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QPoint>
#include <QtPositioning/QGeoCoordinate>

class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

class Viewer3DSitePreloader : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool         busy            READ busy           NOTIFY busyChanged)
    Q_PROPERTY(QString      status          READ status         NOTIFY statusChanged)
    Q_PROPERTY(double       progress        READ progress       NOTIFY progressChanged)
    Q_PROPERTY(QStringList  availableSites  READ availableSites NOTIFY availableSitesChanged)
    Q_PROPERTY(QString      mapsDirectory   READ mapsDirectory  CONSTANT)

public:
    explicit Viewer3DSitePreloader(QObject *parent = nullptr);
    ~Viewer3DSitePreloader();

    bool        busy() const            { return _busy; }
    QString     status() const          { return _status; }
    double      progress() const        { return _progress; }
    QStringList availableSites() const  { return _availableSites; }
    QString     mapsDirectory() const;

    /// Download buildings + satellite tiles for a circle of radiusMeters around center.
    Q_INVOKABLE void preload(const QString &siteName, const QGeoCoordinate &center, double radiusMeters);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void refreshSites();
    Q_INVOKABLE QString sitePath(const QString &siteName) const;
    Q_INVOKABLE QString siteNameFromPath(const QString &path) const;
    Q_INVOKABLE bool deleteSite(const QString &siteName);
    Q_INVOKABLE QString defaultSiteName() const;

signals:
    void busyChanged();
    void statusChanged();
    void progressChanged();
    void availableSitesChanged();
    void preloadFinished(bool ok, QString filePath);

private slots:
    void _osmReplyFinished();
    void _tileFinished();
    void _tileWatchdog();

private:
    void _setBusy(bool busy);
    void _setStatus(const QString &status);
    void _setProgress(double progress);
    void _finish(bool ok, const QString &message);
    void _requestOsm(const QString &serverUrl);
    QString _buildOverpassQuery() const;
    bool _saveOsm(QByteArray data);
    void _startTilePrefetch();
    void _startZoomLevel();
    static QString _sanitize(const QString &name);
    static int _maxTileCount(int zoomLevel, const QGeoCoordinate &coordinateMin, const QGeoCoordinate &coordinateMax);
    static QPoint _latLonToTileXY(const QGeoCoordinate &coordinate, int zoomLevel);

    QNetworkAccessManager*  _networkManager = nullptr;
    QNetworkReply*          _osmReply = nullptr;
    QTimer*                 _watchdog = nullptr;

    bool        _busy = false;
    bool        _cancelled = false;
    QString     _status;
    double      _progress = 0;
    QStringList _availableSites;

    QString         _siteName;
    QGeoCoordinate  _center;
    double          _radiusMeters = 0;
    QGeoCoordinate  _bboxMin;
    QGeoCoordinate  _bboxMax;
    QString         _osmFilePath;
    int             _overpassAttempt = 0;

    // tile prefetch state
    QString _mapType;
    int     _mapId = 0;
    int     _baseZoom = 0;
    int     _zoomLevelsRemaining = 0;
    int     _currentZoom = 0;
    int     _tilesTotal = 0;
    int     _tilesDone = 0;
    int     _tilesFailed = 0;
    int     _tilesTotalAllLevels = 0;
    int     _tilesDoneAllLevels = 0;
};
