#include "VehicleThermalMonitor.h"

#include "AppMessages.h"
#include "AppSettings.h"
#include "MAVLinkLib.h"
#include "QGCLoggingCategory.h"
#include "SettingsManager.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <QtCore/QStringList>

QGC_LOGGING_CATEGORY(VehicleThermalLog, "Vehicle.Thermal")

VehicleThermalMonitor::VehicleThermalMonitor(Vehicle *vehicle)
    : QObject(vehicle), _vehicle(vehicle)
{
    _clock.start();
    auto *settings = SettingsManager::instance()->appSettings();
    for (Fact *fact : {settings->thermalImuSource(), settings->thermalFreshnessMs(),
                       settings->thermalRequireImu(), settings->thermalRequireEsc1(),
                       settings->thermalRequireEsc2(), settings->thermalRequireEsc3(),
                       settings->thermalRequireEsc4()}) {
        connect(fact, &Fact::rawValueChanged, this, [this]() { _configure(); });
    }
    connect(vehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged,
            this, [this](bool lost) { if (lost) _reset(); });
    connect(vehicle, &Vehicle::flyingChanged, this, &VehicleThermalMonitor::refresh);
    connect(vehicle, &Vehicle::landingChanged, this, &VehicleThermalMonitor::refresh);
    connect(vehicle, &Vehicle::armedChanged, this, &VehicleThermalMonitor::refresh);
    _configure();
    _timer.setInterval(250);
    connect(&_timer, &QTimer::timeout, this, &VehicleThermalMonitor::refresh);
    _timer.start();
}

void VehicleThermalMonitor::_configure()
{
    auto *settings = SettingsManager::instance()->appSettings();
    const int source = settings->thermalImuSource()->rawValue().toInt();
    const int timeout = settings->thermalFreshnessMs()->rawValue().toInt();
    if (source < 0 || source > 3 || timeout < 1000 || timeout > 30000) {
        qCWarning(VehicleThermalLog) << "Invalid thermal configuration; IMU source disabled and freshness limited to 3 s";
        _imuSource = 0;
        _timeoutMs = 3000;
        _state.readings[0] = {};
        _alertLatch &= ~1U;
    } else {
        if (_imuSource != source) {
            _state.readings[0] = {};
            _alertLatch &= ~1U;
            _streamsRequested = false;
        }
        _imuSource = source;
        _timeoutMs = timeout;
    }
    _requiredMask = 0;
    const std::array<Fact *, 5> required{
        settings->thermalRequireImu(), settings->thermalRequireEsc1(), settings->thermalRequireEsc2(),
        settings->thermalRequireEsc3(), settings->thermalRequireEsc4()
    };
    for (int i = 0; i < ThermalState::SensorCount; ++i) {
        if (required[i]->rawValue().toBool()) _requiredMask |= 1U << i;
    }
    if (_heardHeartbeat) _requestStreams();
    refresh();
}

void VehicleThermalMonitor::_requestStreams()
{
    if (_streamsRequested || !_heardHeartbeat || _vehicle->vehicleLinkManager()->communicationLost()) return;
    _streamsRequested = true;
    _vehicle->setMessageRate(_vehicle->defaultComponentId(), MAVLINK_MSG_ID_ESC_INFO, 2);
    _vehicle->setMessageRate(_vehicle->defaultComponentId(), MAVLINK_MSG_ID_EXTENDED_SYS_STATE, 2);
    const std::array<uint16_t, 3> imuIds{
        MAVLINK_MSG_ID_SCALED_IMU, MAVLINK_MSG_ID_SCALED_IMU2, MAVLINK_MSG_ID_SCALED_IMU3
    };
    if (_imuSource > 0) _vehicle->setMessageRate(_vehicle->defaultComponentId(), imuIds[_imuSource - 1], 2);
}

void VehicleThermalMonitor::_reset()
{
    _state = {};
    _alertLatch = 0;
    _heardHeartbeat = false;
    _streamsRequested = false;
    refresh();
}

void VehicleThermalMonitor::handleMessage(const mavlink_message_t &message)
{
    if (message.sysid != _vehicle->id() || message.compid != _vehicle->defaultComponentId()) return;
    const int64_t now = _clock.elapsed();
    switch (message.msgid) {
    case MAVLINK_MSG_ID_HEARTBEAT:
        if (!_heardHeartbeat) {
            _heardHeartbeat = true;
            QTimer::singleShot(0, this, &VehicleThermalMonitor::_requestStreams);
        }
        break;
    case MAVLINK_MSG_ID_EXTENDED_SYS_STATE: {
        mavlink_extended_sys_state_t state{};
        mavlink_msg_extended_sys_state_decode(&message, &state);
        ThermalState::Phase phase = ThermalState::Phase::Unknown;
        if (state.landed_state == MAV_LANDED_STATE_ON_GROUND) phase = ThermalState::Phase::Ground;
        if (state.landed_state == MAV_LANDED_STATE_IN_AIR || state.landed_state == MAV_LANDED_STATE_TAKEOFF
            || state.landed_state == MAV_LANDED_STATE_LANDING) phase = ThermalState::Phase::Airborne;
        _state.updatePhase(phase, now);
        break;
    }
    case MAVLINK_MSG_ID_ESC_INFO: {
        mavlink_esc_info_t info{};
        mavlink_msg_esc_info_decode(&message, &info);
        for (int slot = 0; slot < 4; ++slot) {
            const int index = info.index + slot;
            if (index >= 4) continue;
            const bool online = index < info.count && (info.info & (1U << slot));
            const double temperature = info.temperature[slot] == INT16_MAX
                ? qQNaN() : info.temperature[slot] / 100.0;
            _state.update(index + 1, temperature, online, now);
        }
        break;
    }
    case MAVLINK_MSG_ID_SCALED_IMU: {
        if (_imuSource != 1) break;
        mavlink_scaled_imu_t imu{};
        mavlink_msg_scaled_imu_decode(&message, &imu);
        _state.update(0, imu.temperature == 0 ? qQNaN() : imu.temperature / 100.0, true, now);
        break;
    }
    case MAVLINK_MSG_ID_SCALED_IMU2: {
        if (_imuSource != 2) break;
        mavlink_scaled_imu2_t imu{};
        mavlink_msg_scaled_imu2_decode(&message, &imu);
        _state.update(0, imu.temperature == 0 ? qQNaN() : imu.temperature / 100.0, true, now);
        break;
    }
    case MAVLINK_MSG_ID_SCALED_IMU3: {
        if (_imuSource != 3) break;
        mavlink_scaled_imu3_t imu{};
        mavlink_msg_scaled_imu3_decode(&message, &imu);
        _state.update(0, imu.temperature == 0 ? qQNaN() : imu.temperature / 100.0, true, now);
        break;
    }
    default:
        return;
    }
    refresh();
}

QString VehicleThermalMonitor::_sensorName(int index) const
{
    return index == 0 ? tr("FC IMU TEMP") : tr("Motor %1 ESC").arg(index);
}

QString VehicleThermalMonitor::sourceNotice() const
{
    return _imuSource == 0
        ? tr("FC IMU source is unverified. Select a source in development settings only after verifying the installed firmware and physical sensor.")
        : tr("FC IMU TEMP is the configured IMU sensor reading, not a verified board or CPU temperature.");
}

QString VehicleThermalMonitor::_stateText(ThermalState::Availability available, ThermalState::Severity severity) const
{
    if (available == ThermalState::Availability::Stale) return tr("STALE");
    if (available == ThermalState::Availability::Offline) return tr("OFFLINE");
    if (available != ThermalState::Availability::Fresh) return tr("NO DATA");
    if (severity == ThermalState::Severity::Critical) return tr("CRITICAL");
    if (severity == ThermalState::Severity::Warning) return tr("WARNING");
    return tr("NORMAL");
}

void VehicleThermalMonitor::refresh()
{
    const int64_t now = _clock.elapsed();
    _result = _state.evaluate(now, _timeoutMs, _requiredMask);
    _confirmedGround = _state.confirmedGround(now, _timeoutMs)
                       && !_vehicle->flying() && !_vehicle->landing()
                       && !_vehicle->vehicleLinkManager()->communicationLost();
    _groundBlocked = _confirmedGround && _state.blocksGroundCommands(now, _timeoutMs, _requiredMask);
    _sensors.clear();
    QStringList hot;
    QStringList missing;
    for (int i = 0; i < ThermalState::SensorCount; ++i) {
        const auto &reading = _state.readings[i];
        const auto available = _state.availability(i, now, _timeoutMs);
        const bool fresh = available == ThermalState::Availability::Fresh;
        const auto severity = fresh ? ThermalState::severity(reading.temperatureC) : ThermalState::Severity::Unknown;
        const QString state = _stateText(available, severity);
        const QString source = i == 0 ? (_imuSource ? QStringLiteral("SCALED_IMU%1").arg(_imuSource == 1 ? QString() : QString::number(_imuSource))
                                                     : tr("Unverified")) : QStringLiteral("ESC_INFO");
        _sensors.append(QVariantMap{
            {QStringLiteral("name"), _sensorName(i)}, {QStringLiteral("temperatureC"), fresh ? reading.temperatureC : qQNaN()},
            {QStringLiteral("state"), state}, {QStringLiteral("severity"), static_cast<int>(severity)},
            {QStringLiteral("source"), source}, {QStringLiteral("required"), bool(_requiredMask & (1U << i))},
            {QStringLiteral("ageSeconds"), reading.receivedAtMs < 0 ? -1.0 : (now - reading.receivedAtMs) / 1000.0}
        });
        if (_result.criticalMask & (1U << i)) hot << tr("%1: %2 °C").arg(_sensorName(i)).arg(reading.temperatureC, 0, 'f', 2);
        if (_result.missingRequiredMask & (1U << i)) missing << _sensorName(i);
        if (fresh && reading.temperatureC <= 77.0) _alertLatch &= ~(1U << i);
        if (_lastStates[i] != state) {
            qCInfo(VehicleThermalLog) << "Vehicle" << _vehicle->id() << _sensorName(i) << state
                                     << reading.temperatureC << "phase" << static_cast<int>(_state.phase);
            _lastStates[i] = state;
        }
    }
    _reason = !hot.isEmpty() ? tr("Temperature too high (limit 80 °C): %1.").arg(hot.join(QStringLiteral(", ")))
                            : !missing.isEmpty() ? tr("Required temperature data unavailable: %1.").arg(missing.join(QStringLiteral(", ")))
                                                 : QString();
    const unsigned newHot = _result.criticalMask & ~_alertLatch;
    if (newHot && !_confirmedGround && (_vehicle->armed() || _vehicle->flying() || _vehicle->landing())) {
        _alertLatch |= _result.criticalMask;
        QGC::showAppMessage(tr("Vehicle %1: %2 Flight controls have not been changed.").arg(_vehicle->id()).arg(_reason));
    }
    emit updated();
}

bool VehicleThermalMonitor::blockCommand()
{
    refresh();
    if (!_groundBlocked) {
        if (!_confirmedGround && (_result.criticalMask & ~_alertLatch)) {
            _alertLatch |= _result.criticalMask;
            QGC::showAppMessage(tr("Vehicle %1: %2 Ground is not confirmed; flight controls have not been blocked.")
                               .arg(_vehicle->id()).arg(_reason));
        }
        return false;
    }
    qCWarning(VehicleThermalLog) << "Ground command blocked for vehicle" << _vehicle->id() << _reason;
    QGC::showAppMessage(tr("Command blocked by the ground thermal check. %1").arg(_reason));
    return true;
}
