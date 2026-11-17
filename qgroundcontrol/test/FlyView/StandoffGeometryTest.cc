#include "StandoffGeometryTest.h"

#include "FlyViewSettings.h"
#include "QGCGeo.h"
#include "SettingsManager.h"
#include "StandoffGeometry.h"

#include <QtTest/QSignalSpy>

#include <cmath>

namespace {

// Pin the limits to their documented defaults so the tests do not depend on stored settings.
void useDefaultLimits()
{
    FlyViewSettings *settings = SettingsManager::instance()->flyViewSettings();
    settings->standoffMinDistance()->setRawValue(50.0);
    settings->standoffMaxDistance()->setRawValue(1500.0);
    settings->standoffMinHeight()->setRawValue(20.0);
    settings->standoffMaxHeight()->setRawValue(500.0);
    settings->standoffLinkRangeLimit()->setRawValue(15000.0);
}

void setTarget(StandoffGeometry &geometry, double lat, double lon, double altitude = 100.0)
{
    geometry.setTargetLatitude(lat);
    geometry.setTargetLongitude(lon);
    geometry.setTargetAltitude(altitude);
}

}  // namespace

void StandoffGeometryTest::_slotMatchesReference_test()
{
    useDefaultLimits();

    // Reference slots computed independently with the Python geographiclib (WGS-84 Direct).
    struct Case {
        double lat, lon, bearing, distance;
        double expectedLat, expectedLon;
    };
    const Case cases[] = {
        {  47.3764,   8.5481,   0.0,  1000.0,  47.385394563575,    8.548100000000 },
        {  47.3764,   8.5481,  90.0,   100.0,  47.376399992352,    8.549424148678 },
        {  47.3764,   8.5481,  45.0,  1500.0,  47.385939314318,    8.562147251303 },
        {  47.3764,   8.5481, 225.0,    50.0,  47.376081992940,    8.547631845560 },
        { -33.8688, 151.2093, 300.0,   750.0, -33.865418984734,  151.202280466067 },
        {  78.2232,  15.6267, 180.0,  1500.0,  78.209764786774,   15.626700000000 },
        {   0.0,    179.9990,  90.0,  1500.0,   0.000000000000, -179.987525270738 },
    };

    for (const Case &c : cases) {
        StandoffGeometry geometry;
        setTarget(geometry, c.lat, c.lon);
        geometry.setDistance(c.distance);
        geometry.setDirection(c.bearing);

        const QGeoCoordinate slot = geometry.slotCoordinate();
        QVERIFY(slot.isValid());

        // 1e-8 deg is about 1 mm, far inside the 0.5 m acceptance criterion.
        QVERIFY2(std::fabs(slot.latitude() - c.expectedLat) < 1e-8,
                 qPrintable(QString("lat %1 expected %2").arg(slot.latitude(), 0, 'f', 12).arg(c.expectedLat, 0, 'f', 12)));
        QVERIFY2(std::fabs(slot.longitude() - c.expectedLon) < 1e-8,
                 qPrintable(QString("lon %1 expected %2").arg(slot.longitude(), 0, 'f', 12).arg(c.expectedLon, 0, 'f', 12)));
    }
}

void StandoffGeometryTest::_slotAltitudeAndSlantRange_test()
{
    useDefaultLimits();

    StandoffGeometry geometry;
    setTarget(geometry, 47.3764, 8.5481, 120.0);
    geometry.setDistance(100.0);
    geometry.setHeight(100.0);
    geometry.setDirection(0.0);

    QCOMPARE(geometry.slotAltitude(), 220.0);
    QCOMPARE(geometry.slotCoordinate().altitude(), 220.0);
    QVERIFY(std::fabs(geometry.slantRange() - std::sqrt(20000.0)) < 1e-9);

    geometry.setDistance(300.0);
    geometry.setHeight(400.0);
    QVERIFY(std::fabs(geometry.slantRange() - 500.0) < 1e-9);

    // No target altitude: the slot position is still available, its altitude is not.
    geometry.setTargetAltitude(qQNaN());
    QVERIFY(std::isnan(geometry.slotAltitude()));
    QVERIFY(geometry.slotCoordinate().isValid());
}

void StandoffGeometryTest::_slotRoundTrip_test()
{
    useDefaultLimits();

    const double bearings[] = {0.0, 37.5, 90.0, 180.0, 271.0, 359.9};
    for (const double bearing : bearings) {
        StandoffGeometry geometry;
        setTarget(geometry, 47.3764, 8.5481);
        geometry.setDistance(1500.0);
        geometry.setDirection(bearing);

        const QGeoCoordinate target(47.3764, 8.5481);
        const QGeoCoordinate slot = geometry.slotCoordinate();
        QVERIFY(slot.isValid());
        QVERIFY(std::fabs(QGCGeo::geodesicDistance(target, slot) - 1500.0) < 0.01);

        // The slot lies on bearing θ from the target (not the reverse).
        double azimuth = QGCGeo::geodesicAzimuth(target, slot);
        double delta = std::fabs(azimuth - bearing);
        if (delta > 180.0) {
            delta = 360.0 - delta;
        }
        QVERIFY(delta < 1e-3);
    }
}

void StandoffGeometryTest::_validation_test()
{
    useDefaultLimits();

    StandoffGeometry geometry;
    // Fresh model: no target yet.
    QVERIFY(!geometry.valid());
    QVERIFY(!geometry.targetError().isEmpty());
    QVERIFY(!geometry.altitudeError().isEmpty());
    QVERIFY(geometry.distanceError().isEmpty());    // default R = 100
    QVERIFY(geometry.heightError().isEmpty());      // default H = 100
    QVERIFY(geometry.directionError().isEmpty());   // default θ = 0
    QCOMPARE(geometry.distance(), StandoffGeometry::kDefaultDistance);
    QCOMPARE(geometry.height(), StandoffGeometry::kDefaultHeight);

    setTarget(geometry, 47.3764, 8.5481, 120.0);
    QVERIFY(geometry.valid());

    // Target
    geometry.setTargetLatitude(90.5);
    QVERIFY(!geometry.targetError().isEmpty());
    geometry.setTargetLatitude(-90.5);
    QVERIFY(!geometry.targetError().isEmpty());
    geometry.setTargetLatitude(47.3764);
    geometry.setTargetLongitude(180.5);
    QVERIFY(!geometry.targetError().isEmpty());
    geometry.setTargetLongitude(qQNaN());
    QVERIFY(!geometry.targetError().isEmpty());
    geometry.setTargetLongitude(8.5481);
    QVERIFY(geometry.targetError().isEmpty());

    // Altitude is required
    geometry.setTargetAltitude(qQNaN());
    QVERIFY(!geometry.altitudeError().isEmpty());
    QVERIFY(!geometry.valid());
    geometry.setTargetAltitude(0.0);
    QVERIFY(geometry.altitudeError().isEmpty());

    // Direction: 0 <= θ < 360
    geometry.setDirection(-0.1);
    QVERIFY(!geometry.directionError().isEmpty());
    geometry.setDirection(360.0);
    QVERIFY(!geometry.directionError().isEmpty());
    geometry.setDirection(qQNaN());
    QVERIFY(!geometry.directionError().isEmpty());
    geometry.setDirection(359.999);
    QVERIFY(geometry.directionError().isEmpty());
    geometry.setDirection(0.0);
    QVERIFY(geometry.directionError().isEmpty());

    // Distance / height required
    geometry.setDistance(qQNaN());
    QVERIFY(!geometry.distanceError().isEmpty());
    geometry.setDistance(100.0);
    geometry.setHeight(qQNaN());
    QVERIFY(!geometry.heightError().isEmpty());
    geometry.setHeight(100.0);
    QVERIFY(geometry.valid());
}

void StandoffGeometryTest::_limitsAreInclusive_test()
{
    useDefaultLimits();

    StandoffGeometry geometry;
    setTarget(geometry, 47.3764, 8.5481);

    geometry.setDistance(50.0);
    QVERIFY(geometry.distanceError().isEmpty());
    geometry.setDistance(49.99);
    QVERIFY(!geometry.distanceError().isEmpty());
    geometry.setDistance(1500.0);
    QVERIFY(geometry.distanceError().isEmpty());
    geometry.setDistance(1500.01);
    QVERIFY(!geometry.distanceError().isEmpty());
    // An out-of-limit R is flagged but the draft slot is still computed for the map.
    QVERIFY(geometry.slotCoordinate().isValid());
    QVERIFY(!geometry.valid());
    geometry.setDistance(100.0);

    geometry.setHeight(20.0);
    QVERIFY(geometry.heightError().isEmpty());
    geometry.setHeight(19.99);
    QVERIFY(!geometry.heightError().isEmpty());
    geometry.setHeight(500.0);
    QVERIFY(geometry.heightError().isEmpty());
    geometry.setHeight(500.01);
    QVERIFY(!geometry.heightError().isEmpty());
    geometry.setHeight(100.0);
    QVERIFY(geometry.valid());

    // The limits follow the settings.
    SettingsManager::instance()->flyViewSettings()->standoffMaxDistance()->setRawValue(80.0);
    QCOMPARE(geometry.maxDistance(), 80.0);
    geometry.setDistance(100.0);
    QVERIFY(!geometry.distanceError().isEmpty());
    useDefaultLimits();
    QVERIFY(geometry.distanceError().isEmpty());
}

void StandoffGeometryTest::_gcsRangeAndLinkWarning_test()
{
    useDefaultLimits();

    StandoffGeometry geometry;
    setTarget(geometry, 47.3764, 8.5481);
    geometry.setDistance(1000.0);
    geometry.setDirection(0.0);

    // No GCS position: nothing to measure, no warning.
    QVERIFY(std::isnan(geometry.gcsDistanceToSlot()));
    QVERIFY(!geometry.linkRangeExceeded());

    // GCS 10 km south of the target; slot 1 km north of the target (reference: 11000 m).
    geometry.setGcsCoordinate(QGeoCoordinate(47.286453584201, 8.548100000000));
    QVERIFY(std::fabs(geometry.gcsDistanceToSlot() - 11000.0) < 0.01);
    QVERIFY(!geometry.linkRangeExceeded());

    // GCS 16 km south of the target (reference: 17000 m), beyond the 15 km limit.
    geometry.setGcsCoordinate(QGeoCoordinate(47.232485053849, 8.548100000000));
    QVERIFY(std::fabs(geometry.gcsDistanceToSlot() - 17000.0) < 0.01);
    QVERIFY(geometry.linkRangeExceeded());
    // The warning never blocks: the inputs are still valid.
    geometry.setTargetAltitude(100.0);
    QVERIFY(geometry.valid());
}

void StandoffGeometryTest::_changedSignal_test()
{
    useDefaultLimits();

    StandoffGeometry geometry;
    QSignalSpy spy(&geometry, &StandoffGeometry::changed);

    geometry.setTargetLatitude(47.0);
    QCOMPARE(spy.count(), 1);
    geometry.setTargetLatitude(47.0);              // unchanged
    QCOMPARE(spy.count(), 1);
    geometry.setTargetLongitude(qQNaN());          // NaN -> NaN is not a change
    QCOMPARE(spy.count(), 1);
    geometry.setDistance(200.0);
    geometry.setHeight(150.0);
    geometry.setDirection(10.0);
    geometry.setTargetAltitude(10.0);
    QCOMPARE(spy.count(), 5);
    geometry.setGcsCoordinate(QGeoCoordinate(47.0, 8.0));
    QCOMPARE(spy.count(), 6);
    geometry.setGcsCoordinate(QGeoCoordinate(47.0, 8.0));
    QCOMPARE(spy.count(), 6);

    // Changing a limit setting re-notifies so bindings re-evaluate validation.
    SettingsManager::instance()->flyViewSettings()->standoffMinHeight()->setRawValue(30.0);
    QVERIFY(spy.count() > 6);
    useDefaultLimits();
}

void StandoffGeometryTest::_slotUnavailableWithoutTarget_test()
{
    useDefaultLimits();

    StandoffGeometry geometry;
    QVERIFY(!geometry.slotCoordinate().isValid());
    QVERIFY(std::isnan(geometry.slotAltitude()));
    QVERIFY(!geometry.valid());

    // Slot needs lat/lon, R and a valid bearing; it does not need an altitude.
    geometry.setTargetLatitude(47.3764);
    QVERIFY(!geometry.slotCoordinate().isValid());
    geometry.setTargetLongitude(8.5481);
    QVERIFY(geometry.slotCoordinate().isValid());
    geometry.setDirection(400.0);
    QVERIFY(!geometry.slotCoordinate().isValid());
}

UT_REGISTER_TEST(StandoffGeometryTest, TestLabel::Unit, TestLabel::Utilities)
