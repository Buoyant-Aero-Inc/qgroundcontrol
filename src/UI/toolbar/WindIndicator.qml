/****************************************************************************
 *
 * Custom build (Buoyant Aero): real-time surface wind indicator.
 *
 * Shows wind direction, speed and the maximum gust in the last hour from the
 * most reliable weather station within a radius of the vehicle (or the map
 * centre when no vehicle is connected), plus the model wind at the operating
 * altitude. Sources: Synoptic Data (token) or Iowa Mesonet current obs
 * (ASOS/AWOS airports, RWIS, DCP…), Open-Meteo for winds aloft.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.MultiVehicleManager
import QGroundControl.ScreenTools
import QGroundControl.Palette

Item {
    id:             control
    width:          windRow.width
    anchors.top:    parent.top
    anchors.bottom: parent.bottom

    property bool   showIndicator:  _settings.windEnabled.rawValue

    property var    _settings:      QGroundControl.settingsManager.flyViewSettings
    property var    _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool   _imperial:      true   // aviation: always knots

    // ---- data ----
    property var    stations:       []
    property var    best:           null        // {id,name,net,distMi,ageMin,spdKt,dirDeg,gustKt}
    property real   maxGustHrKt:    NaN
    property var    aloft:          null        // {speedKt, dirDeg, zFt, source}
    property string status:         qsTr("no data")
    property bool   fresh:          false
    property real   lastFetch:      0

    function kt(v) { return isNaN(v) || v === null ? "--" : (_imperial ? v.toFixed(0) + " kt" : (v / 1.94384).toFixed(1) + " m/s") }
    function ktShort(v) { return isNaN(v) || v === null ? "--" : (_imperial ? v.toFixed(0) : (v / 1.94384).toFixed(0)) }

    function refCoordinate() {
        if (_activeVehicle && _activeVehicle.coordinate.isValid && _activeVehicle.coordinate.latitude !== 0) return _activeVehicle.coordinate
        return QGroundControl.flightMapPosition
    }

    function distMi(lat1, lon1, lat2, lon2) {
        var R = 3958.8, p1 = lat1 * Math.PI / 180, p2 = lat2 * Math.PI / 180, dp = (lat2 - lat1) * Math.PI / 180, dl = (lon2 - lon1) * Math.PI / 180
        var a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2)
        return 2 * R * Math.asin(Math.sqrt(a))
    }
    function netRank(net) {
        net = String(net || "").toUpperCase()
        if (/ASOS|AWOS|^1$/.test(net)) return 0
        if (/RAWS|^2$/.test(net)) return 1
        if (/RWIS|DOT/.test(net)) return 2
        if (/DCP|USCRN|SCAN|COOP/.test(net)) return 3
        if (/CWOP|APRS|^65$/.test(net)) return 4
        return 5
    }
    function get(url, cb, headers) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        if (headers) for (var k in headers) { try { xhr.setRequestHeader(k, headers[k]) } catch (e) {} }
        xhr.onreadystatechange = function() { if (xhr.readyState === XMLHttpRequest.DONE) cb(xhr.status, xhr.responseText) }
        xhr.send()
    }

    function refresh() {
        var c = refCoordinate()
        if (!c || !c.isValid) { status = qsTr("no position"); return }
        var lat = c.latitude, lon = c.longitude
        var radius = _settings.windStationRadius.rawValue
        var token = _settings.windSynopticToken.rawValue.trim()
        status = qsTr("updating…")
        // winds aloft (Open-Meteo, 80/120 m)
        get("https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&hourly=wind_speed_10m,wind_speed_80m,wind_speed_120m,wind_direction_80m,wind_direction_120m,wind_gusts_10m&wind_speed_unit=kn&forecast_days=1&timezone=auto", function(st, txt) {
            if (st !== 200) return
            try {
                var h = JSON.parse(txt).hourly, i = new Date().getHours()
                var zM = _settings.windAltitudeFt.rawValue / 3.28084
                var f = Math.max(0, Math.min(1.3, Math.log(zM / 80) / Math.log(120 / 80)))
                var spd = zM <= 80 ? h.wind_speed_10m[i] + (h.wind_speed_80m[i] - h.wind_speed_10m[i]) * Math.max(0, Math.log(zM / 10) / Math.log(8)) : h.wind_speed_80m[i] + (h.wind_speed_120m[i] - h.wind_speed_80m[i]) * f
                var dir = h.wind_direction_80m[i]
                aloft = { speedKt: spd, dirDeg: dir, zFt: _settings.windAltitudeFt.rawValue, gust10Kt: h.wind_gusts_10m[i], source: "Open-Meteo" }
            } catch (e) { console.log("wind aloft parse", e) }
        })
        if (token !== "") {
            get("https://api.synopticdata.com/v2/stations/latest?token=" + encodeURIComponent(token) + "&radius=" + lat + "," + lon + "," + radius + "&vars=wind_speed,wind_direction,wind_gust&within=90&units=english&status=active", function(st, txt) {
                if (st !== 200) { fetchIEM(lat, lon, radius); return }
                try {
                    var j = JSON.parse(txt); if (!j.STATION) { fetchIEM(lat, lon, radius); return }
                    var list = []
                    for (var i = 0; i < j.STATION.length; i++) {
                        var s = j.STATION[i], o = s.OBSERVATIONS || {}, ws = o.wind_speed_value_1 || {}, wd = o.wind_direction_value_1 || {}, wg = o.wind_gust_value_1 || {}
                        if (ws.value === undefined) continue
                        var t = ws.date_time ? Date.parse(ws.date_time) : NaN
                        list.push({ id: s.STID, name: s.NAME, net: s.MNET_ID, distMi: Number(s.DISTANCE), ageMin: isNaN(t) ? NaN : (Date.now() - t) / 60000, spdKt: ws.value * 0.868976, dirDeg: wd.value === undefined ? NaN : wd.value, gustKt: wg.value === undefined ? NaN : wg.value * 0.868976, src: "Synoptic" })
                    }
                    finishStations(list, token)
                } catch (e) { fetchIEM(lat, lon, radius) }
            })
        } else {
            fetchIEM(lat, lon, radius)
        }
    }

    function fetchIEM(lat, lon, radius) {
        var state = _settings.windStateCode.rawValue.trim().toUpperCase()
        var go = function(stCode) {
            get("https://mesonet.agron.iastate.edu/api/1/currents.json?state=" + stCode, function(st, txt) {
                if (st !== 200) { status = qsTr("station fetch failed"); return }
                try {
                    var d = JSON.parse(txt).data, list = []
                    for (var i = 0; i < d.length; i++) {
                        var x = d[i]
                        if (typeof x.lat !== "number" || x.sknt === null || x.sknt === undefined) continue
                        var dm = distMi(lat, lon, x.lat, x.lon); if (dm > radius) continue
                        var t = x.utc_valid ? Date.parse(x.utc_valid) : NaN
                        list.push({ id: x.station, name: x.name || x.station, net: x.network, distMi: dm, ageMin: isNaN(t) ? NaN : (Date.now() - t) / 60000, spdKt: x.sknt, dirDeg: x.drct === null ? NaN : x.drct, gustKt: (x.gust === null || x.gust === undefined) ? NaN : x.gust, src: "IEM " + x.network })
                    }
                    finishStations(list, "")
                } catch (e) { status = qsTr("station parse failed") }
            })
        }
        if (state === "" || state === "AUTO") {
            // resolve state from NWS; fall back to CA
            get("https://api.weather.gov/points/" + lat.toFixed(4) + "," + lon.toFixed(4), function(st, txt) {
                var code = "CA"
                try { if (st === 200) code = JSON.parse(txt).properties.relativeLocation.properties.state || "CA" } catch (e) {}
                go(code)
            }, { "Accept": "application/geo+json", "User-Agent": "QGC-Buoyant-Wind/1.0" })
        } else go(state)
    }

    function finishStations(list, token) {
        var ok = list.filter(function(s) { return !isNaN(s.ageMin) && s.ageMin < 120 })
        ok.sort(function(a, b) { return (netRank(a.net) - netRank(b.net)) || (Math.floor(a.ageMin / 20) - Math.floor(b.ageMin / 20)) || (a.distMi - b.distMi) })
        stations = ok
        best = ok.length ? ok[0] : null
        lastFetch = Date.now()
        if (!best) { status = qsTr("no station within %1 mi").arg(_settings.windStationRadius.rawValue); maxGustHrKt = NaN; return }
        status = best.id + " · " + best.distMi.toFixed(1) + " mi · " + Math.round(best.ageMin) + " min"
        maxGustHrKt = isNaN(best.gustKt) ? best.spdKt : best.gustKt
        // max gust over the last hour
        if (token !== "" && best.src === "Synoptic") {
            var f = function(d) { return d.toISOString().replace(/[-:]/g, "").slice(0, 12) }
            var end = new Date(), start = new Date(end.getTime() - 3600000)
            get("https://api.synopticdata.com/v2/stations/timeseries?token=" + encodeURIComponent(token) + "&stid=" + best.id + "&start=" + f(start) + "&end=" + f(end) + "&vars=wind_speed,wind_gust&units=english", function(st, txt) {
                if (st !== 200) return
                try { var o = JSON.parse(txt).STATION[0].OBSERVATIONS, vals = [].concat(o.wind_gust_set_1 || [], o.wind_speed_set_1 || []).filter(function(v) { return typeof v === "number" }); if (vals.length) maxGustHrKt = Math.max.apply(null, vals) * 0.868976 } catch (e) {}
            })
        } else if (/ASOS/i.test(best.net || "")) {
            var e2 = new Date(), s2 = new Date(e2.getTime() - 3600000), id = best.id.replace(/^K/, "")
            var q = "station=" + id + "&data=sknt,gust&year1=" + s2.getUTCFullYear() + "&month1=" + (s2.getUTCMonth() + 1) + "&day1=" + s2.getUTCDate() + "&hour1=" + s2.getUTCHours() + "&minute1=" + s2.getUTCMinutes() + "&year2=" + e2.getUTCFullYear() + "&month2=" + (e2.getUTCMonth() + 1) + "&day2=" + e2.getUTCDate() + "&hour2=" + e2.getUTCHours() + "&minute2=" + e2.getUTCMinutes() + "&tz=UTC&format=onlycomma&latlon=no&missing=M&trace=T&direct=no&report_type=3&report_type=4"
            get("https://mesonet.agron.iastate.edu/cgi-bin/request/asos.py?" + q, function(st, txt) {
                if (st !== 200) return
                var mx = NaN, lines = txt.split("\n")
                for (var i = 1; i < lines.length; i++) { var c = lines[i].split(","); for (var k = 2; k < 4; k++) { var n = parseFloat(c[k]); if (!isNaN(n)) mx = isNaN(mx) ? n : Math.max(mx, n) } }
                if (!isNaN(mx)) maxGustHrKt = Math.max(mx, isNaN(best.gustKt) ? 0 : best.gustKt)
            })
        }
    }

    Timer {
        interval:           Math.max(1, _settings.windRefreshMinutes.rawValue) * 60000
        running:            control.showIndicator
        repeat:             true
        triggeredOnStart:   true
        onTriggered:        control.refresh()
    }
    Timer { interval: 15000; running: control.showIndicator; repeat: true; onTriggered: fresh = (Date.now() - lastFetch) < 2 * Math.max(1, _settings.windRefreshMinutes.rawValue) * 60000 + 30000 }

    property color _col: !best ? qgcPal.colorGrey : (maxGustHrKt >= _settings.windGustWarnKt.rawValue ? qgcPal.colorRed : (maxGustHrKt >= _settings.windGustWarnKt.rawValue * 0.7 ? qgcPal.colorYellow : qgcPal.colorGreen))

    Row {
        id:                     windRow
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        spacing:                ScreenTools.defaultFontPixelWidth * 0.5

        // wind arrow: points in the direction the wind is blowing TO
        Item {
            width:  height
            height: parent.height * 0.8
            anchors.verticalCenter: parent.verticalCenter
            QGCLabel {
                anchors.centerIn:   parent
                text:               "➤"
                font.pointSize:     ScreenTools.largeFontPointSize
                color:              control._col
                rotation:           best && !isNaN(best.dirDeg) ? (best.dirDeg + 90) % 360 : 0
                opacity:            best && !isNaN(best.dirDeg) ? 1 : 0.35
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            QGCLabel {
                text:           best ? (ktShort(best.spdKt) + " G " + ktShort(maxGustHrKt)) : qsTr("wind --")
                font.pointSize: ScreenTools.defaultFontPointSize
                color:          control._col
            }
            QGCLabel {
                text:           best ? (isNaN(best.dirDeg) ? "" : best.dirDeg.toFixed(0) + "° ") + best.id : qsTr("no stn")
                font.pointSize: ScreenTools.smallFontPointSize
                color:          fresh ? qgcPal.text : qgcPal.colorGrey
            }
        }
    }

    MouseArea {
        anchors.fill:   parent
        onClicked:      mainWindow.showIndicatorDrawer(windPage, control)
    }

    Component {
        id: windPage

        ToolIndicatorPage {
            showExpand: false

            contentComponent: Component {
                ColumnLayout {
                    spacing: ScreenTools.defaultFontPixelHeight / 2

                    SettingsGroupLayout {
                        heading: qsTr("Surface wind — %1").arg(control.best ? control.best.id : qsTr("no station"))

                        LabelledLabel { label: qsTr("Wind");                 labelText: control.best ? control.kt(control.best.spdKt) + qsTr(" from ") + (isNaN(control.best.dirDeg) ? "--" : control.best.dirDeg.toFixed(0) + "°") : "--" }
                        LabelledLabel { label: qsTr("Max gust, last hour");  labelText: control.kt(control.maxGustHrKt) }
                        LabelledLabel { label: qsTr("Latest gust");          labelText: control.best ? control.kt(control.best.gustKt) : "--" }
                        LabelledLabel { label: qsTr("Station");              labelText: control.best ? (control.best.name + " (" + control.best.src + ")") : "--" }
                        LabelledLabel { label: qsTr("Distance / age");       labelText: control.best ? (control.best.distMi.toFixed(1) + " mi · " + Math.round(control.best.ageMin) + " min") : "--" }
                        LabelledLabel { label: qsTr("Status");               labelText: control.status }
                    }

                    SettingsGroupLayout {
                        heading: qsTr("Wind aloft (model) at %1 ft").arg(control._settings.windAltitudeFt.rawValue)

                        LabelledLabel { label: qsTr("Wind");         labelText: control.aloft ? control.kt(control.aloft.speedKt) + qsTr(" from ") + control.aloft.dirDeg.toFixed(0) + "°" : "--" }
                        LabelledLabel { label: qsTr("Model sfc gust"); labelText: control.aloft ? control.kt(control.aloft.gust10Kt) : "--" }
                        LabelledLabel { label: qsTr("Source");       labelText: control.aloft ? control.aloft.source : "--" }
                    }

                    SettingsGroupLayout {
                        heading: qsTr("Other stations in range (%1)").arg(control.stations.length)
                        visible: control.stations.length > 1

                        Repeater {
                            model: control.stations.slice(1, 6)
                            LabelledLabel {
                                label:      modelData.id + " · " + modelData.distMi.toFixed(1) + " mi"
                                labelText:  control.ktShort(modelData.spdKt) + " G " + control.ktShort(modelData.gustKt) + (isNaN(modelData.dirDeg) ? "" : " · " + modelData.dirDeg.toFixed(0) + "°") + " · " + Math.round(modelData.ageMin) + " min"
                            }
                        }
                    }

                    QGCButton {
                        Layout.alignment: Qt.AlignHCenter
                        text:             qsTr("Refresh now")
                        onClicked:        control.refresh()
                    }
                }
            }
        }
    }
}
