#include "VehicleTargetTrackFactGroup.h"
#include "Vehicle.h"

#include <QtCore/QDateTime>

VehicleTargetTrackFactGroup::VehicleTargetTrackFactGroup(QObject *parent)
    : FactGroup(200, QStringLiteral(":/json/Vehicle/TargetTrackFact.json"), parent)
{
    _addFact(&_statusFact);
    _addFact(&_targetIdFact);
    _addFact(&_topLeftXFact);
    _addFact(&_topLeftYFact);
    _addFact(&_botRightXFact);
    _addFact(&_botRightYFact);
    _addFact(&_confidenceFact);

    // Start "idle": nothing tracked, box hidden.
    _statusFact.setRawValue(StatusIdle);
    _targetIdFact.setRawValue(0);
    _topLeftXFact.setRawValue(qQNaN());
    _topLeftYFact.setRawValue(qQNaN());
    _botRightXFact.setRawValue(qQNaN());
    _botRightYFact.setRawValue(qQNaN());
    _confidenceFact.setRawValue(qQNaN());

    // Link-staleness watchdog: each frame restarts it; on timeout we drop back to
    // IDLE so the overlay hides the box rather than freezing the last position.
    _staleTimer.setSingleShot(true);
    _staleTimer.setInterval(_staleTimeoutMSecs);
    (void) connect(&_staleTimer, &QTimer::timeout, this, &VehicleTargetTrackFactGroup::_checkStale);
}

void VehicleTargetTrackFactGroup::handleMessage(Vehicle *vehicle, const mavlink_message_t &message)
{
    Q_UNUSED(vehicle);

    if (message.msgid != MAVLINK_MSG_ID_NEXAM_TARGET_TRACK) {
        return;
    }

    mavlink_nexam_target_track_t track{};
    mavlink_msg_nexam_target_track_decode(&message, &track);

    status()->setRawValue(track.status);
    targetId()->setRawValue(track.target_id);
    topLeftX()->setRawValue(track.top_left_x);
    topLeftY()->setRawValue(track.top_left_y);
    botRightX()->setRawValue(track.bot_right_x);
    botRightY()->setRawValue(track.bot_right_y);
    confidence()->setRawValue(track.confidence);

    _lastUpdateMs = QDateTime::currentMSecsSinceEpoch();
    emit lastUpdateChanged();
    _setTelemetryAvailable(true);
    _staleTimer.start();
}

void VehicleTargetTrackFactGroup::registerSelection(int videoSource, qint64 timestampMs)
{
    _selectionVideoSource = (videoSource == 1) ? 1 : 0;
    _selectionTimestampMs = timestampMs;
    emit selectionChanged();
}

void VehicleTargetTrackFactGroup::clear()
{
    _staleTimer.stop();
    _statusFact.setRawValue(StatusIdle);
    _targetIdFact.setRawValue(0);
    _topLeftXFact.setRawValue(qQNaN());
    _topLeftYFact.setRawValue(qQNaN());
    _botRightXFact.setRawValue(qQNaN());
    _botRightYFact.setRawValue(qQNaN());
    _confidenceFact.setRawValue(qQNaN());
    _lastUpdateMs = 0;
    emit lastUpdateChanged();
    _setTelemetryAvailable(false);
}

void VehicleTargetTrackFactGroup::_checkStale()
{
    // Stream stopped or tracker went quiet. Drop to IDLE so the overlay hides the
    // box instead of leaving a stale rectangle pinned to the last position.
    clear();
}
