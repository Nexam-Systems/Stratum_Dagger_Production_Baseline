#include "FlyViewArmedTimerTest.h"
#include "Vehicle.h"
#include "AppSettings.h"
#include "SettingsManager.h"
#include "VideoSettings.h"

#include <QtCore/qscopeguard.h>
#include <QtCore/QCoreApplication>
#include <QtCore/QEvent>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlEngine>
#include <QtQml/QQmlExpression>
#include <QtTest/QSignalSpy>

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

void FlyViewArmedTimerTest::_flightTimePropertyRetainsCppOwnership()
{
    VehicleFactGroup facts;
    Fact *const flightTime = facts.flightTime();
    QCOMPARE(facts.getFact(QStringLiteral("flightTime")), flightTime);
    QSignalSpy destroyedSpy(flightTime, &QObject::destroyed);

    {
        QQmlEngine engine;
        QQmlContext context(engine.rootContext());
        context.setContextProperty(QStringLiteral("vehicleFacts"), &facts);
        QQmlExpression expression(&context, nullptr, QStringLiteral("vehicleFacts.flightTime"));
        const QVariant result = expression.evaluate();
        QVERIFY2(!expression.hasError(), qPrintable(expression.error().toString()));
        QCOMPARE(result.value<Fact *>(), flightTime);
        QCOMPARE(QQmlEngine::objectOwnership(flightTime), QQmlEngine::CppOwnership);
        engine.collectGarbage();
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        QCOMPARE(destroyedSpy.count(), 0);
    }

    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QCOMPARE(destroyedSpy.count(), 0);
    flightTime->setRawValue(42);
    QCOMPARE(flightTime->rawValue().toInt(), 42);
}

UT_REGISTER_TEST(FlyViewArmedTimerTest, TestLabel::Unit, TestLabel::Vehicle)