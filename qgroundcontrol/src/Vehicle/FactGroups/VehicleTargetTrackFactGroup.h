#pragma once

#include "FactGroup.h"

#include <QtCore/QTimer>

// STRATUM: live vehicle facts decoded from the custom NEXAM_TARGET_TRACK (42004)
// message streamed by the companion tracker (mission computer) once per processed
// video frame during an operator-designated visual track. Drives the moving
// tracked-target box drawn over the video in the FlyView.
//
// The companion runs the OpenCV tracker; STRATUM only sends the initial selection
// (NEXAM_TARGET_SELECT / 42003, see Vehicle::sendTargetSelect) and renders whatever
// box the companion reports back here. Coordinates are normalized to the video
// frame (0..1, origin top-left) so they are resolution-independent.
//
// Staleness: the FactGroup base only throttles UI updates; it has no link-drop
// timeout. We add one so that when the 42004 stream stops (link/stream drop, or
// the tracker loses lock and goes quiet) the overlay stops drawing a frozen box.
class VehicleTargetTrackFactGroup : public FactGroup
{
    Q_OBJECT

    Q_PROPERTY(Fact *status     READ status     CONSTANT)
    Q_PROPERTY(Fact *targetId   READ targetId   CONSTANT)
    Q_PROPERTY(Fact *topLeftX   READ topLeftX   CONSTANT)
    Q_PROPERTY(Fact *topLeftY   READ topLeftY   CONSTANT)
    Q_PROPERTY(Fact *botRightX  READ botRightX  CONSTANT)
    Q_PROPERTY(Fact *botRightY  READ botRightY  CONSTANT)
    Q_PROPERTY(Fact *confidence READ confidence CONSTANT)
    Q_PROPERTY(qint64 lastUpdateMs READ lastUpdateMs NOTIFY lastUpdateChanged)
    Q_PROPERTY(qint64 selectionTimestampMs READ selectionTimestampMs NOTIFY selectionChanged)
    Q_PROPERTY(int selectionVideoSource READ selectionVideoSource NOTIFY selectionChanged)

public:
    explicit VehicleTargetTrackFactGroup(QObject *parent = nullptr);

    Fact *status()     { return &_statusFact; }
    Fact *targetId()   { return &_targetIdFact; }
    Fact *topLeftX()   { return &_topLeftXFact; }
    Fact *topLeftY()   { return &_topLeftYFact; }
    Fact *botRightX()  { return &_botRightXFact; }
    Fact *botRightY()  { return &_botRightYFact; }
    Fact *confidence() { return &_confidenceFact; }
    qint64 lastUpdateMs() const { return _lastUpdateMs; }
    qint64 selectionTimestampMs() const { return _selectionTimestampMs; }
    int selectionVideoSource() const { return _selectionVideoSource; }

    Q_INVOKABLE void registerSelection(int videoSource, qint64 timestampMs);
    Q_INVOKABLE void clear();

    // Tracker status enum, mirroring the message field.
    enum TrackStatus {
        StatusIdle     = 0,
        StatusTracking = 1,
        StatusLost     = 2,
    };

    // Overrides from FactGroup
    void handleMessage(Vehicle *vehicle, const mavlink_message_t &message) final;

signals:
    void lastUpdateChanged();
    void selectionChanged();

private slots:
    void _checkStale();

private:
    Fact _statusFact     = Fact(0, QStringLiteral("status"),     FactMetaData::valueTypeUint8);
    Fact _targetIdFact   = Fact(0, QStringLiteral("targetId"),   FactMetaData::valueTypeUint8);
    Fact _topLeftXFact   = Fact(0, QStringLiteral("topLeftX"),   FactMetaData::valueTypeFloat);
    Fact _topLeftYFact   = Fact(0, QStringLiteral("topLeftY"),   FactMetaData::valueTypeFloat);
    Fact _botRightXFact  = Fact(0, QStringLiteral("botRightX"),  FactMetaData::valueTypeFloat);
    Fact _botRightYFact  = Fact(0, QStringLiteral("botRightY"),  FactMetaData::valueTypeFloat);
    Fact _confidenceFact = Fact(0, QStringLiteral("confidence"), FactMetaData::valueTypeFloat);

    QTimer _staleTimer;
    qint64 _lastUpdateMs = 0;
    qint64 _selectionTimestampMs = 0;
    int _selectionVideoSource = -1;

    // Tracker nominally streams at video frame rate (>=15 Hz). Treat the track as
    // stale after ~300 ms of silence so a brief hiccup does not flicker the box, but
    // a real drop / lost lock clears it.
    static constexpr int _staleTimeoutMSecs = 300;
};
