#include "FlyViewArmedTimerTest.h"
#include "Vehicle.h"
#include "AppSettings.h"
#include "SettingsManager.h"
#include "VideoSettings.h"

#include <QtCore/qscopeguard.h>

void FlyViewArmedTimerTest::_observedArmingResetsAndDisarmingFreezes()
{
    auto *disableVideo = SettingsManager::instance()->videoSettings()->disableWhenDisarmed();
    const auto previous = disableVideo->rawValue();
    const auto restore = qScopeGuard([&]() { disableVideo->setRawValue(previous); });
    disableVideo->setRawValue(false);
    Vehicle vehicle(MAV_AUTOPILOT_PX4, MAV_TYPE_QUADROTOR);
    vehicle._updateArmed(false);
    vehicle._updateArmed(true);
    QVERIFY(!vehicle.armedTimerSinceConnection());
    QTest::qWait(40);
    vehicle._updateArmed(false);
    const double frozen = vehicle.getFact("flightTime")->rawValue().toDouble();
    QVERIFY(frozen > 0);
    QTest::qWait(40);
    QCOMPARE(vehicle.getFact("flightTime")->rawValue().toDouble(), frozen);
    vehicle._updateArmed(true);
    QCOMPARE(vehicle.getFact("flightTime")->rawValue().toDouble(), 0.0);
    QVERIFY(!vehicle.armedTimerSinceConnection());
    vehicle._updateArmed(false);
}

void FlyViewArmedTimerTest::_alreadyArmedConnectionIsLabeled()
{
    Vehicle vehicle(MAV_AUTOPILOT_PX4, MAV_TYPE_QUADROTOR);
    vehicle._updateArmed(true);
    QVERIFY(vehicle.armedTimerSinceConnection());
}

UT_REGISTER_TEST(FlyViewArmedTimerTest, TestLabel::Unit, TestLabel::Vehicle)