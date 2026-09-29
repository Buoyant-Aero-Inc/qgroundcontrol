/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include "SettingsGroup.h"

class FlyViewSettings : public SettingsGroup
{
    Q_OBJECT
public:
    FlyViewSettings(QObject* parent = nullptr);

    DEFINE_SETTING_NAME_GROUP()

    DEFINE_SETTINGFACT(guidedMinimumAltitude)
    DEFINE_SETTINGFACT(guidedMaximumAltitude)
    DEFINE_SETTINGFACT(showLogReplayStatusBar)
    DEFINE_SETTINGFACT(showAdditionalIndicatorsCompass)
    DEFINE_SETTINGFACT(lockNoseUpCompass)
    DEFINE_SETTINGFACT(maxGoToLocationDistance)
    DEFINE_SETTINGFACT(forwardFlightGoToLocationLoiterRad)
    DEFINE_SETTINGFACT(goToLocationRequiresConfirmInGuided)
    DEFINE_SETTINGFACT(keepMapCenteredOnVehicle)
    DEFINE_SETTINGFACT(showSimpleCameraControl)
    DEFINE_SETTINGFACT(showObstacleDistanceOverlay)
    DEFINE_SETTINGFACT(updateHomePosition)
    DEFINE_SETTINGFACT(instrumentQmlFile2)
    DEFINE_SETTINGFACT(requestControlAllowTakeover)
    DEFINE_SETTINGFACT(requestControlTimeout)
    DEFINE_SETTINGFACT(vehicleIconSizeScale)
    DEFINE_SETTINGFACT(vehicleIconColor)
    DEFINE_SETTINGFACT(liveTrackingEnabled)
    DEFINE_SETTINGFACT(liveTrackingServerUrl)
    DEFINE_SETTINGFACT(liveTrackingInterval)
    DEFINE_SETTINGFACT(windEnabled)
    DEFINE_SETTINGFACT(windStationRadius)
    DEFINE_SETTINGFACT(windRefreshMinutes)
    DEFINE_SETTINGFACT(windAltitudeFt)
    DEFINE_SETTINGFACT(windGustWarnKt)
    DEFINE_SETTINGFACT(windSynopticToken)
    DEFINE_SETTINGFACT(windStateCode)
};
