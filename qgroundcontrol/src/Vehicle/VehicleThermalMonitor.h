#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtQmlIntegration/QtQmlIntegration>

#include "MAVLinkMessageType.h"
#include "ThermalState.h"

class Vehicle;

class VehicleThermalMonitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
    Q_PROPERTY(QVariantList sensors READ sensors NOTIFY updated)
    Q_PROPERTY(double averageC READ averageC NOTIFY updated)
    Q_PROPERTY(int freshCount READ freshCount NOTIFY updated)
    Q_PROPERTY(int severity READ severity NOTIFY updated)
    Q_PROPERTY(bool groundBlocked READ groundBlocked NOTIFY updated)
    Q_PROPERTY(bool preflightReady READ preflightReady NOTIFY updated)
    Q_PROPERTY(bool confirmedGround READ confirmedGround NOTIFY updated)
    Q_PROPERTY(QString reason READ reason NOTIFY updated)
    Q_PROPERTY(QString sourceNotice READ sourceNotice NOTIFY updated)

public:
    explicit VehicleThermalMonitor(Vehicle *vehicle);
    void handleMessage(const mavlink_message_t &message);
    bool blockCommand();
    void refresh();

    QVariantList sensors() const { return _sensors; }
    double averageC() const { return _result.averageC; }
    int freshCount() const { return _result.freshCount; }
    int severity() const { return static_cast<int>(_result.severity); }
    bool groundBlocked() const { return _groundBlocked; }
    bool preflightReady() const { return !_result.criticalMask && !_result.missingRequiredMask; }
    bool confirmedGround() const { return _confirmedGround; }
    QString reason() const { return _reason; }
    QString sourceNotice() const;

signals:
    void updated();

private:
    void _configure();
    void _requestStreams();
    void _reset();
    QString _sensorName(int index) const;
    QString _stateText(ThermalState::Availability availability, ThermalState::Severity severity) const;

    Vehicle *_vehicle;
    ThermalState _state;
    ThermalState::Result _result;
    QElapsedTimer _clock;
    QTimer _timer;
    QVariantList _sensors;
    QString _reason;
    std::array<QString, ThermalState::SensorCount> _lastStates{};
    unsigned _requiredMask = 0;
    unsigned _alertLatch = 0;
    int _imuSource = 0;
    int _timeoutMs = 3000;
    bool _heardHeartbeat = false;
    bool _streamsRequested = false;
    bool _confirmedGround = false;
    bool _groundBlocked = false;
};
