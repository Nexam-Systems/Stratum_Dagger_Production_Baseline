#include "VehicleThermalMonitor.h"

#include "AppMessages.h"
#include "MAVLinkLib.h"
#include "QGCLoggingCategory.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <QtCore/QStringList>

QGC_LOGGING_CATEGORY(VehicleThermalLog, "Vehicle.Thermal")

VehicleThermalMonitor::VehicleThermalMonitor(Vehicle *vehicle)
    : QObject(vehicle), _vehicle(vehicle)
{
    _clock.start();
    connect(vehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged,
            this, [this](bool lost) { if (lost) _reset(); });
    connect(vehicle, &Vehicle::flyingChanged, this, &VehicleThermalMonitor::refresh);
    connect(vehicle, &Vehicle::landingChanged, this, &VehicleThermalMonitor::refresh);
    connect(vehicle, &Vehicle::armedChanged, this, &VehicleThermalMonitor::refresh);
    refresh();
    _timer.setInterval(250);
    connect(&_timer, &QTimer::timeout, this, &VehicleThermalMonitor::refresh);
    _timer.start();
}

void VehicleThermalMonitor::_requestStreams()
{
    if (_streamsRequested || !_heardHeartbeat || _vehicle->vehicleLinkManager()->communicationLost()) return;
    _streamsRequested = true;
    _vehicle->setMessageRate(_vehicle->defaultComponentId(), MAVLINK_MSG_ID_ESC_INFO, 2);
    _vehicle->setMessageRate(_vehicle->defaultComponentId(), MAVLINK_MSG_ID_EXTENDED_SYS_STATE, 2);
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
            if (index >= ThermalState::SensorCount) continue;
            const bool online = index < info.count && (info.info & (1U << slot));
            const double temperature = info.temperature[slot] == INT16_MAX
                ? qQNaN() : info.temperature[slot] / 100.0;
            _state.update(index, temperature, online, now);
        }
        break;
    }
    default:
        return;
    }
    refresh();
}

QString VehicleThermalMonitor::_sensorName(int index) const
{
    return tr("Motor %1").arg(index + 1);
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
    _result = _state.evaluate(now, FreshnessTimeoutMs);
    _confirmedGround = _state.confirmedGround(now, FreshnessTimeoutMs)
                       && !_vehicle->flying() && !_vehicle->landing()
                       && !_vehicle->vehicleLinkManager()->communicationLost();
    _groundBlocked = _confirmedGround && _state.blocksGroundCommands(now, FreshnessTimeoutMs);
    _sensors.clear();
    QStringList hot;
    for (int i = 0; i < ThermalState::SensorCount; ++i) {
        const auto &reading = _state.readings[i];
        const auto available = _state.availability(i, now, FreshnessTimeoutMs);
        const bool fresh = available == ThermalState::Availability::Fresh;
        const auto severity = fresh ? ThermalState::severity(reading.temperatureC) : ThermalState::Severity::Unknown;
        const QString state = _stateText(available, severity);
        _sensors.append(QVariantMap{
            {QStringLiteral("name"), _sensorName(i)}, {QStringLiteral("temperatureC"), fresh ? reading.temperatureC : qQNaN()},
            {QStringLiteral("severity"), static_cast<int>(severity)}
        });
        if (_result.criticalMask & (1U << i)) hot << tr("%1: %2 °C").arg(_sensorName(i)).arg(reading.temperatureC, 0, 'f', 2);
        if (fresh && reading.temperatureC <= 77.0) _alertLatch &= ~(1U << i);
        if (_lastStates[i] != state) {
            qCInfo(VehicleThermalLog) << "Vehicle" << _vehicle->id() << _sensorName(i) << state
                                     << reading.temperatureC << "phase" << static_cast<int>(_state.phase);
            _lastStates[i] = state;
        }
    }
    _reason = !hot.isEmpty() ? tr("Temperature too high (limit 80 °C): %1.").arg(hot.join(QStringLiteral(", ")))
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
