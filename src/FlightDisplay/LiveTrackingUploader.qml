/****************************************************************************
 *
 * (c) 2009-2026 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick

import QGroundControl

// Custom build: streams the active vehicle's position to a live tracking server
// (Firebase Realtime Database REST endpoint) so customers can follow the flight
// on a shared web link, and so the tracking page can compute live impressions.
//
// Writes two things every interval:
//   PUT <serverUrl>/current.json          -> latest position snapshot
//   PUT <serverUrl>/trail/<ts>.json       -> trail entry used for impressions/history
Item {
    id: _root

    visible: false

    property var  _flyViewSettings: QGroundControl.settingsManager.flyViewSettings
    property var  _activeVehicle:   QGroundControl.multiVehicleManager.activeVehicle

    property bool trackingEnabled:  _flyViewSettings.liveTrackingEnabled.rawValue
    property string serverUrl:      _flyViewSettings.liveTrackingServerUrl.rawValue

    // Status for UI badges
    property bool lastUploadOk:     false
    property real lastUploadTime:   0
    property int  uploadCount:      0

    Timer {
        id:               uploadTimer
        interval:         Math.max(1, _flyViewSettings.liveTrackingInterval.rawValue) * 1000
        running:          _root.trackingEnabled && _root.serverUrl !== ""
        repeat:           true
        triggeredOnStart: true
        onTriggered:      _root._upload()
    }

    function _baseUrl() {
        var base = serverUrl.toString().trim()
        while (base.endsWith("/")) {
            base = base.slice(0, -1)
        }
        return base
    }

    function _upload() {
        var vehicle = _activeVehicle
        if (!vehicle || !vehicle.coordinate.isValid) {
            return
        }
        var base = _baseUrl()
        if (base === "") {
            return
        }

        var now = Date.now()
        var heading = vehicle.heading.rawValue
        var home = vehicle.homePosition
        var batt = (vehicle.batteries && vehicle.batteries.count > 0) ? vehicle.batteries.get(0) : null
        var payload = {
            "lat":     vehicle.coordinate.latitude,
            "lon":     vehicle.coordinate.longitude,
            "alt":     vehicle.altitudeRelative.rawValue,
            "heading": isNaN(heading) ? 0 : heading,
            "speed":   vehicle.groundSpeed.rawValue,
            "homeLat": home.isValid ? home.latitude : null,
            "homeLon": home.isValid ? home.longitude : null,
            "homeAlt": home.isValid ? home.altitude : null,
            "ts":      now,
            // Extended telemetry for the ops 3D app (all optional, null if unavailable)
            "altAmsl":    _num(vehicle.altitudeAMSL),
            "climb":      _num(vehicle.climbRate),
            "airspeed":   _num(vehicle.airSpeed),
            "roll":       _num(vehicle.roll),
            "pitch":      _num(vehicle.pitch),
            "throttle":   _num(vehicle.throttlePct),
            "battPct":    batt ? _num(batt.percentRemaining) : null,
            "battV":      batt ? _num(batt.voltage) : null,
            "battA":      batt ? _num(batt.current) : null,
            "sats":       vehicle.gps ? _num(vehicle.gps.count) : null,
            "hdop":       vehicle.gps ? _num(vehicle.gps.hdop) : null,
            "mode":       vehicle.flightMode,
            "armed":      vehicle.armed,
            "flightTime": _num(vehicle.flightTime),
            "flightDist": _num(vehicle.flightDistance),
            "distHome":   _num(vehicle.distanceToHome)
        }

        _put(base + "/current.json", payload, true)
        _put(base + "/trail/" + now + ".json", { "lat": payload.lat, "lon": payload.lon, "alt": payload.alt, "heading": payload.heading, "ts": now }, false)
    }

    // Fact -> number or null (facts can be missing or NaN before first telemetry)
    function _num(fact) {
        if (!fact) return null
        var v = fact.rawValue
        return (v === undefined || v === null || isNaN(v)) ? null : Number(v)
    }

    function _put(url, obj, trackStatus) {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", url)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && trackStatus) {
                _root.lastUploadOk = (xhr.status >= 200 && xhr.status < 300)
                _root.lastUploadTime = Date.now()
                if (_root.lastUploadOk) {
                    _root.uploadCount = _root.uploadCount + 1
                }
            }
        }
        xhr.send(JSON.stringify(obj))
    }
}
