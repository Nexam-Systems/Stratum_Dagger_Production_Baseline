#include "FirmwareCompatibilityTest.h"
#include "AdminSettings.h"
#include "SettingsManager.h"
#include "Vehicle.h"

#include <QtCore/QRegularExpression>
#include <QtCore/qscopeguard.h>

void FirmwareCompatibilityTest::_compatibilityToggle_data()
{
    QTest::addColumn<bool>("checksEnabled");
    QTest::addColumn<int>("reportedMinor");
    QTest::addColumn<int>("reportedNxPatch");
    QTest::addColumn<bool>("markerValid");
    QTest::addColumn<int>("schemaMajor");
    QTest::addColumn<bool>("baseAccepted");
    QTest::addColumn<bool>("nxAccepted");

    QTest::newRow("enabled-exact") << true << 14 << 0 << true << 1 << true << true;
    QTest::newRow("enabled-newer-base") << true << 18 << 0 << true << 1 << false << true;
    QTest::newRow("enabled-older-base") << true << 13 << 0 << true << 1 << false << true;
    QTest::newRow("enabled-newer-nx") << true << 14 << 1 << true << 1 << true << false;
    QTest::newRow("enabled-missing-marker") << true << 14 << 0 << false << 1 << true << false;
    QTest::newRow("enabled-wrong-schema") << true << 14 << 0 << true << 2 << true << false;
    QTest::newRow("disabled-mismatch") << false << 18 << 1 << true << 2 << true << true;
    QTest::newRow("disabled-missing-marker") << false << 14 << 0 << false << 0 << true << true;
    QTest::newRow("disabled-no-version") << false << -1 << -1 << false << 0 << true << true;
    QTest::newRow("enabled-no-version") << true << -1 << -1 << false << 0 << false << false;
}

void FirmwareCompatibilityTest::_compatibilityToggle()
{
    QFETCH(bool, checksEnabled);
    QFETCH(int, reportedMinor);
    QFETCH(int, reportedNxPatch);
    QFETCH(bool, markerValid);
    QFETCH(int, schemaMajor);
    QFETCH(bool, baseAccepted);
    QFETCH(bool, nxAccepted);

    auto *admin = SettingsManager::instance()->adminSettings();
    const QList<Fact *> settings{
        admin->firmwareCompatibilityChecksEnabled(), admin->strictCompatibilityGate(),
        admin->requiredPx4MajorVersion(), admin->requiredPx4MinorVersion(), admin->requiredPx4PatchVersion(),
        admin->requiredStratumNxMajor(), admin->requiredStratumNxMinor(), admin->requiredStratumNxPatch(),
        admin->requiredStratumSchemaMajor()
    };
    QVariantList previous;
    for (auto *fact : settings) previous.append(fact->rawValue());
    const auto restore = qScopeGuard([&]() {
        for (int index = 0; index < settings.size(); ++index) settings[index]->setRawValue(previous[index]);
    });
    const QVariantList required{checksEnabled, false, 1, 14, 0, 1, 0, 0, 1};
    for (int index = 0; index < settings.size(); ++index) settings[index]->setRawValue(required[index]);

    ignoreLogMessage("Vehicle.Vehicle", QtWarningMsg, QRegularExpression("STRATUM .*version check:"));
    Vehicle vehicle(MAV_AUTOPILOT_PX4, MAV_TYPE_QUADROTOR);
    if (reportedMinor >= 0) vehicle.setFirmwareVersion(1, reportedMinor, 0);
    if (reportedNxPatch >= 0) vehicle.setFirmwareCustomVersion(1, 0, reportedNxPatch);
    if (reportedNxPatch >= 0) vehicle.setNxCapabilities(schemaMajor, 0, 0, markerValid);
    QCOMPARE(vehicle.checkPx4VersionAgainstAdminFloor(), baseAccepted);
    QCOMPARE(vehicle.checkStratumCustomVersionAgainstAdminFloor(), nxAccepted);
}

UT_REGISTER_TEST(FirmwareCompatibilityTest, TestLabel::Unit, TestLabel::Vehicle)