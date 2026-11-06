#include "VehicleThermalMonitorTest.h"

#include "MAVLinkLib.h"
#include "Vehicle.h"

#include <QtCore/QRegularExpression>
#include <QtTest/QSignalSpy>

void VehicleThermalMonitorTest::_sourcesAndGroundCommandGuard()
{
    ignoreLogMessage("Vehicle.Thermal", QtWarningMsg, QRegularExpression("Ground command blocked"));
    ignoreLogMessage("API.QGCApplication.AppMessage", QtDebugMsg, QRegularExpression("thermal check|Temperature too high"));

    Vehicle vehicle(MAV_AUTOPILOT_PX4, MAV_TYPE_QUADROTOR);
    auto *monitor = vehicle.thermal();
    QVERIFY(monitor);
    QCOMPARE(monitor->sensors().size(), 4);
    QCOMPARE(monitor->freshCount(), 0);

    mavlink_message_t message{};
    mavlink_scaled_imu_t imu{};
    imu.temperature = 9000;
    mavlink_msg_scaled_imu_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &imu);
    monitor->handleMessage(message);
    QCOMPARE(monitor->freshCount(), 0); // IMU readings no longer participate.
    QVERIFY(monitor->preflightReady());

    mavlink_esc_info_t info{};
    info.index = 0;
    info.count = 4;
    info.info = 15;
    for (int i = 0; i < 4; ++i) info.temperature[i] = 4000 + i * 1000;
    info.temperature[3] = 8000;
    mavlink_msg_esc_info_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &info);
    monitor->handleMessage(message);
    QCOMPARE(monitor->averageC(), 57.5);
    QVERIFY(monitor->preflightReady());
    mavlink_msg_scaled_imu_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &imu);
    monitor->handleMessage(message);
    mavlink_scaled_imu2_t imu2{};
    imu2.temperature = 9000;
    mavlink_msg_scaled_imu2_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &imu2);
    monitor->handleMessage(message);
    mavlink_scaled_imu3_t imu3{};
    imu3.temperature = 9000;
    mavlink_msg_scaled_imu3_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &imu3);
    monitor->handleMessage(message);
    QCOMPARE(monitor->averageC(), 57.5);
    QVERIFY(monitor->preflightReady());

    info.temperature[2] = 8100;
    mavlink_msg_esc_info_encode(vehicle.id(), MAV_COMP_ID_CAMERA, &message, &info);
    monitor->handleMessage(message);
    mavlink_msg_esc_info_encode(vehicle.id() + 1, vehicle.defaultComponentId(), &message, &info);
    monitor->handleMessage(message);
    QCOMPARE(monitor->averageC(), 57.5);
    mavlink_msg_esc_info_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &info);
    monitor->handleMessage(message);
    QCOMPARE(monitor->freshCount(), 4);
    QVERIFY(monitor->averageC() < 80.0);
    QVERIFY(!monitor->preflightReady());
    QVERIFY(!monitor->groundBlocked()); // Flight phase remains unknown.
    mavlink_extended_sys_state_t phase{};
    phase.landed_state = MAV_LANDED_STATE_ON_GROUND;
    mavlink_msg_extended_sys_state_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &phase);
    monitor->handleMessage(message);
    QVERIFY(monitor->groundBlocked());
    QVERIFY(monitor->reason().contains(QStringLiteral("Motor 3")));

    QSignalSpy results(&vehicle, &Vehicle::mavCommandResult);
    vehicle.sendMavCommand(vehicle.defaultComponentId(), MAV_CMD_COMPONENT_ARM_DISARM, false, 1, 2989);
    QCOMPARE(results.count(), 1);
    QCOMPARE(results.takeFirst()[3].toInt(), static_cast<int>(MAV_RESULT_DENIED));

    struct Reply { int calls = 0; mavlink_command_ack_t ack{}; } reply;
    Vehicle::MavCmdAckHandlerInfo_t handler{};
    handler.resultHandlerData = &reply;
    handler.resultHandler = [](void *data, int, const mavlink_command_ack_t &ack, Vehicle::MavCmdResultFailureCode_t) {
        auto *reply = static_cast<Reply *>(data);
        ++reply->calls;
        reply->ack = ack;
    };
    vehicle.sendMavCommandWithHandler(&handler, vehicle.defaultComponentId(), MAV_CMD_NAV_TAKEOFF);
    QCOMPARE(reply.calls, 1);
    QCOMPARE(reply.ack.command, static_cast<uint16_t>(MAV_CMD_NAV_TAKEOFF));
    QCOMPARE(reply.ack.result, static_cast<uint8_t>(MAV_RESULT_DENIED));
    QVERIFY(vehicle.thermalCommandAllowed(MAV_CMD_COMPONENT_ARM_DISARM, 0));
    QVERIFY(!vehicle.thermalCommandAllowed(MAV_CMD_DO_SET_MODE));

    bool fallbackCalled = false;
    vehicle.sendMavCommandWithLambdaFallback([&]() { fallbackCalled = true; },
        vehicle.defaultComponentId(), MAV_CMD_NAV_TAKEOFF, false);
    QVERIFY(!fallbackCalled);

    phase.landed_state = MAV_LANDED_STATE_IN_AIR;
    mavlink_msg_extended_sys_state_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &phase);
    monitor->handleMessage(message);
    QVERIFY(!monitor->groundBlocked());
    QVERIFY(vehicle.thermalCommandAllowed(MAV_CMD_COMPONENT_ARM_DISARM, 1));
    QVERIFY(vehicle.thermalCommandAllowed(MAV_CMD_NAV_TAKEOFF));
    QVERIFY(vehicle.thermalCommandAllowed(MAV_CMD_DO_SET_MODE));

    info.temperature[2] = INT16_MAX;
    mavlink_msg_esc_info_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &info);
    monitor->handleMessage(message);
    QCOMPARE(monitor->freshCount(), 3);
    QVERIFY(!monitor->groundBlocked());
    phase.landed_state = MAV_LANDED_STATE_ON_GROUND;
    mavlink_msg_extended_sys_state_encode(vehicle.id(), vehicle.defaultComponentId(), &message, &phase);
    monitor->handleMessage(message);
    QVERIFY(!monitor->groundBlocked());
    QVERIFY(monitor->preflightReady());
    QVERIFY(monitor->reason().isEmpty());
}

UT_REGISTER_TEST(VehicleThermalMonitorTest, TestLabel::Unit, TestLabel::Vehicle)
