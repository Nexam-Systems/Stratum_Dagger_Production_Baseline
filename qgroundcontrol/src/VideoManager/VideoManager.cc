#include "VideoManager.h"
#include "AppSettings.h"
#include "MavlinkCameraControlInterface.h"
#include "MultiVehicleManager.h"
#include "AppMessages.h"
#include "QGCApplication.h"
#include "QGCCameraManager.h"
#include "QGCCorePlugin.h"
#include "QGCLoggingCategory.h"
#include "QGCVideoStreamInfo.h"
#include "SettingsManager.h"
#include "SubtitleWriter.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"
#include "VideoReceiver.h"
#include "VideoSettings.h"
#include "QtMultimediaReceiver.h"
#include "UVCReceiver.h"
#ifdef QGC_GST_STREAMING
#include "GStreamerHelpers.h"
#include "GStreamer.h"
#if defined(QGC_HAS_ANY_GPU_PATH)
#include "VideoReceiver/GStreamer/HwBuffers/QGCRhiCapture.h"
#endif
#include <QtMultimedia/QVideoSink>
#include <QtMultimediaQuick/private/qquickvideooutput_p.h>
#endif

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QApplicationStatic>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QElapsedTimer>
#include <QtCore/QEventLoop>
#include <QtCore/QFile>
#include <QtCore/QFutureWatcher>
#include <QtCore/QPointer>
#include <QtCore/QRunnable>
#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtNetwork/QUdpSocket>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

#include <atomic>
#include <cmath>

QGC_LOGGING_CATEGORY(VideoManagerLog, "Video.VideoManager")

static constexpr const char *kFileExtension[VideoReceiver::FILE_FORMAT_MAX + 1] = {
    "mkv",
    "mov",
    "mp4"
};

Q_APPLICATION_STATIC(VideoManager, _videoManagerInstance);

bool VideoManager::_shouldSkipGStreamerForUnitTests()
{
    return qgcApp() && QGC::runningUnitTests() && !qEnvironmentVariableIsSet("QGC_TEST_ENABLE_GSTREAMER");
}

VideoManager::VideoManager(QObject *parent)
    : QObject(parent)
    , _subtitleWriter(new SubtitleWriter(this))
    , _videoSettings(SettingsManager::instance()->videoSettings())
{
    qCDebug(VideoManagerLog) << this;
    (void) qRegisterMetaType<VideoReceiver::STATUS>("STATUS");

#ifdef QGC_GST_STREAMING
    _gstreamerDisabledForUnitTests = _shouldSkipGStreamerForUnitTests();
    if (_gstreamerDisabledForUnitTests) {
        qCInfo(VideoManagerLog) << "Skipping GStreamer initialization for unit tests";
    }
#endif
}

VideoManager::~VideoManager()
{
    qCDebug(VideoManagerLog) << this;
}

// STRATUM: current C12 gimbal IP. Reads videoSettings.daggerC12Host; falls back to the
// factory default so a missing/empty setting doesn't silently break the camera.
static QString _daggerC12Host()
{
    auto *vs = SettingsManager::instance() ? SettingsManager::instance()->videoSettings() : nullptr;
    const QString stored = vs ? vs->daggerC12Host()->rawValue().toString().trimmed() : QString();
    return stored.isEmpty() ? QStringLiteral("192.168.144.108") : stored;
}

bool VideoManager::sendCameraAction(const QString &action)
{
    const QString normalizedAction = action.trimmed().toLower();
    QByteArray payload;
    if (normalizedAction == "zoom-in") {
        payload = QByteArrayLiteral("#TPUD2wDZM0A65");
    } else if (normalizedAction == "zoom-out") {
        payload = QByteArrayLiteral("#TPUD2wDZM0B66");
    } else if (normalizedAction == "zoom-1x") {
        payload = QByteArrayLiteral("#TPUD2wDZM0155");
    } else if (normalizedAction == "zoom-2x") {
        payload = QByteArrayLiteral("#TPUD2wDZM0256");
    } else if (normalizedAction == "zoom-3x") {
        payload = QByteArrayLiteral("#TPUD2wDZM0357");
    } else if (normalizedAction == "zoom-4x") {
        payload = QByteArrayLiteral("#TPUD2wDZM0458");
    } else if (normalizedAction == "pan-up") {
        payload = QByteArrayLiteral("#TPUG2wGSP1E6C");
    } else if (normalizedAction == "pan-down") {
        payload = QByteArrayLiteral("#TPUG2wGSPE26D");
    } else if (normalizedAction == "tilt-left") {
        payload = QByteArrayLiteral("#TPUG2wGSYE276");
    } else if (normalizedAction == "tilt-right") {
        payload = QByteArrayLiteral("#TPUG2wGSY1E75");
    } else if (normalizedAction == "stop") {
        payload = QByteArrayLiteral("#TPUG2wPTZ006A");
    } else if (normalizedAction == "center") {
        payload = QByteArrayLiteral("#TPUG2wPTZ056F");
    } else if (normalizedAction == "capture") {
        payload = QByteArrayLiteral("#TPUD2wCAP013E");
    } else if (normalizedAction == "rec-start") {
        payload = QByteArrayLiteral("#TPUD2wREC0144");
    } else if (normalizedAction == "rec-stop") {
        payload = QByteArrayLiteral("#TPUD2wREC0043");
    } else if (normalizedAction == "track-center") {
        // STRATUM: previously sent #TPUG8wGOT + #TPUG2wSUM01 on :5000. Field
        // testing (and the Skydroid reference PC app) confirmed those never
        // actually engage the C12's on-camera tracker. The working path is the
        // AI V1.2.0 binary protocol on :1030 with a SET_REGION rectangle,
        // preceded by TRACK_CONTROL/enable_ai. Do that here with a small centre
        // region so the pre-existing "track-center" button still works.
        return sendC12TrackRegion(0.42, 0.36, 0.58, 0.64, 0);
    } else if (normalizedAction == "track-stop") {
        return stopC12Track();
    } else if (normalizedAction == "track-ack") {
        return setC12AiEnabled(true);
    } else if (normalizedAction == "palette-off") {
        payload = QByteArrayLiteral("#TPUD2wIMG0046");
    } else if (normalizedAction == "palette-01") {
        payload = QByteArrayLiteral("#TPUD2wIMG0147");
    } else if (normalizedAction == "palette-03") {
        payload = QByteArrayLiteral("#TPUD2wIMG0349");
    } else if (normalizedAction == "palette-04") {
        payload = QByteArrayLiteral("#TPUD2wIMG044A");
    } else if (normalizedAction == "palette-05") {
        payload = QByteArrayLiteral("#TPUD2wIMG054B");
    } else if (normalizedAction == "palette-06") {
        payload = QByteArrayLiteral("#TPUD2wIMG064C");
    } else if (normalizedAction == "palette-07") {
        payload = QByteArrayLiteral("#TPUD2wIMG074D");
    } else if (normalizedAction == "palette-08") {
        payload = QByteArrayLiteral("#TPUD2wIMG084E");
    } else if (normalizedAction == "palette-09") {
        payload = QByteArrayLiteral("#TPUD2wIMG094F");
    } else if (normalizedAction == "palette-0a") {
        payload = QByteArrayLiteral("#TPUD2wIMG0A57");
    } else if (normalizedAction == "palette-0b") {
        payload = QByteArrayLiteral("#TPUD2wIMG0B58");
    } else if (normalizedAction == "palette-0c") {
        payload = QByteArrayLiteral("#TPUD2wIMG0C59");
    } else {
        return false;
    }

    QUdpSocket socket;
    const QHostAddress host(_daggerC12Host());
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "sendCameraAction: invalid C12 host" << _daggerC12Host();
        return false;
    }
    return socket.writeDatagram(payload, host, 5000) == payload.size();
}

bool VideoManager::sendCameraTrackPoint(int x, int y)
{
    // STRATUM: back this compatibility shim with the AI protocol (Python's main.py
    // proves SUM 01 + GOT on :5000 do NOT engage the C12 tracker). Convert the
    // 1280x720 pixel point into a 160x160 normalized region and delegate.
    const qreal cx = qBound(0.0, qreal(x) / 1280.0, 1.0);
    const qreal cy = qBound(0.0, qreal(y) / 720.0, 1.0);
    const qreal hw = 80.0 / 1280.0;
    const qreal hh = 80.0 / 720.0;
    return sendC12TrackRegion(qMax(0.0, cx - hw), qMax(0.0, cy - hh),
                              qMin(1.0, cx + hw), qMin(1.0, cy + hh), 0);
}

// STRATUM: Reprogram the C12 gimbal's IP. Skydroid "IPV" set command:
//   #TPUD<LEN><w>IPV<newIp><CHK>
// where LEN is the payload length as a single hex nibble (IPv4 dotted-quad is
// 7..15 chars so it always fits) and CHK is (sum of all preceding bytes) & 0xFF,
// formatted as two uppercase hex chars. The camera reboots on the new IP.
bool VideoManager::setC12CameraIp(const QString &newIp)
{
    const QString trimmed = newIp.trimmed();
    const QHostAddress addr(trimmed);
    if (addr.isNull() || addr.protocol() != QAbstractSocket::IPv4Protocol) {
        qCWarning(VideoManagerLog) << "setC12CameraIp: invalid IPv4 address" << trimmed;
        return false;
    }
    const QByteArray ipBytes = trimmed.toUtf8();
    if (ipBytes.size() < 7 || ipBytes.size() > 15) {
        qCWarning(VideoManagerLog) << "setC12CameraIp: IP length out of range" << trimmed;
        return false;
    }

    const QByteArray lenHex = QByteArray::number(ipBytes.size(), 16).toUpper();
    QByteArray base = QByteArrayLiteral("#TPUD") + lenHex + QByteArrayLiteral("wIPV") + ipBytes;
    int sum = 0;
    for (int i = 0; i < base.size(); ++i) {
        sum += static_cast<unsigned char>(base.at(i));
    }
    const QByteArray payload = base + QByteArray::number(sum & 0xFF, 16).toUpper().rightJustified(2, '0');

    const QString currentHost = _daggerC12Host();
    const QHostAddress host(currentHost);
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "setC12CameraIp: invalid current host" << currentHost;
        return false;
    }
    QUdpSocket socket;
    if (socket.writeDatagram(payload, host, 5000) != payload.size()) {
        qCWarning(VideoManagerLog) << "setC12CameraIp: UDP send failed to" << currentHost;
        return false;
    }

    // Persist the new address so every subsequent C12 command goes to the reprogrammed
    // camera. Camera reboots and comes up on this IP shortly.
    if (auto *vs = SettingsManager::instance() ? SettingsManager::instance()->videoSettings() : nullptr) {
        vs->daggerC12Host()->setRawValue(trimmed);
    }
    qCInfo(VideoManagerLog) << "setC12CameraIp: sent set-IP" << trimmed << "to" << currentHost;
    return true;
}

// STRATUM: Ask the C12 gimbal for its actual IP with `#TPUD2rIPV0053` (uppercase
// equivalent of the doc's `#tpUD2rIPV0093`). The camera answers with
// `#TPUD<L>rIPV<ip><chk>` (case-insensitive) on the same UDP socket. Returns
// an empty string if the camera doesn't reply within timeoutMs.
QString VideoManager::readC12CameraIp(int timeoutMs)
{
    const QString currentHost = _daggerC12Host();
    const QHostAddress host(currentHost);
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "readC12CameraIp: invalid current host" << currentHost;
        return QString();
    }

    QUdpSocket socket;
    if (!socket.bind(QHostAddress::AnyIPv4, 0)) {
        qCWarning(VideoManagerLog) << "readC12CameraIp: bind failed" << socket.errorString();
        return QString();
    }
    // Send both prefix cases: we know the C12 accepts uppercase writes, but the
    // protocol doc's rIPV example uses lowercase and some firmware is picky.
    static const QByteArray kReadIpUpper = QByteArrayLiteral("#TPUD2rIPV0053");
    static const QByteArray kReadIpLower = QByteArrayLiteral("#tpUD2rIPV0093");
    if (socket.writeDatagram(kReadIpUpper, host, 5000) != kReadIpUpper.size()
        || socket.writeDatagram(kReadIpLower, host, 5000) != kReadIpLower.size()) {
        qCWarning(VideoManagerLog) << "readC12CameraIp: send failed to" << currentHost;
        return QString();
    }

    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < timeoutMs) {
        const int remaining = timeoutMs - static_cast<int>(timer.elapsed());
        if (!socket.waitForReadyRead(qMax(1, remaining))) {
            continue;
        }
        while (socket.hasPendingDatagrams()) {
            QByteArray buf(static_cast<int>(socket.pendingDatagramSize()), Qt::Uninitialized);
            socket.readDatagram(buf.data(), buf.size());
            int matchIdx = buf.indexOf("rIPV");
            if (matchIdx < 0) {
                matchIdx = buf.indexOf("RIPV");
            }
            if (matchIdx < 1) {
                continue;
            }
            bool ok = false;
            const int len = QString(QChar(buf.at(matchIdx - 1))).toInt(&ok, 16);
            if (!ok || len < 7 || len > 15 || buf.size() < matchIdx + 4 + len) {
                continue;
            }
            const QString ip = QString::fromLatin1(buf.mid(matchIdx + 4, len));
            const QHostAddress a(ip);
            if (a.isNull() || a.protocol() != QAbstractSocket::IPv4Protocol) {
                continue;
            }
            qCInfo(VideoManagerLog) << "readC12CameraIp: camera at" << currentHost << "reports IP" << ip;
            return ip;
        }
    }
    qCInfo(VideoManagerLog) << "readC12CameraIp: no reply from" << currentHost << "within" << timeoutMs << "ms";
    return QString();
}

// STRATUM: C12 gimbal-attitude support (Skydroid TOP protocol V1.1.6 §3.3.2).
//
// Enabling: send #TPUG2wGAA<rateHex>  (rate 01..64 hex = 1..100 Hz, 00 = off).
// Stream:   #TP<addr><C><r>GAC Y0Y1Y2Y3 P0P1P2P3 R0R1R2R3 CC
//           Each 4-char group is signed int16 in 0.01° units, high byte first
//           (e.g. 'EC78' = 0xEC78 = -5000 = -50.00°). CC = (sum & 0xFF) as 2-hex.
// Socket:   persistent so the camera keeps our source port stable; the reply
//           lands on the same port. Frames land in _onC12AttitudeDatagram().
static constexpr int    kC12AttitudeRateHz            = 5;
// STRATUM: attitude is pushed into the vehicle-messages drawer at the raw camera
// rate so the operator sees a continuous stream of yaw/pitch/roll under the ARM
// button. If this becomes too chatty in real flight, raise this to 500 ms.
static constexpr int    kC12AttitudeReportIntervalMs  = 0;
static constexpr quint16 kC12ControlPort              = 5000;
static constexpr int    kSeverityInfo                 = 6;  // MAV_SEVERITY_INFO
static constexpr int    kSeverityWarning              = 4;  // MAV_SEVERITY_WARNING

static QByteArray _c12BuildFrame(const char addr[2], char lenHex, char ctrl,
                                 const char flag[3], const QByteArray &data)
{
    QByteArray base;
    base.reserve(3 + 2 + 1 + 1 + 3 + data.size() + 2);
    base.append('#'); base.append('T'); base.append('P');
    base.append(addr, 2);
    base.append(lenHex);
    base.append(ctrl);
    base.append(flag, 3);
    base.append(data);
    int sum = 0;
    for (int i = 0; i < base.size(); ++i) sum += static_cast<unsigned char>(base.at(i));
    base += QByteArray::number(sum & 0xFF, 16).toUpper().rightJustified(2, '0');
    return base;
}

void VideoManager::_ensureC12Socket()
{
    if (_c12Socket) return;
    _c12Socket = new QUdpSocket(this);
    if (!_c12Socket->bind(QHostAddress::AnyIPv4, 0, QUdpSocket::DontShareAddress)) {
        qCWarning(VideoManagerLog) << "C12 attitude socket bind failed:"
                                   << _c12Socket->errorString();
    }
    (void) connect(_c12Socket, &QUdpSocket::readyRead,
                   this, &VideoManager::_onC12AttitudeDatagram);
}

void VideoManager::_enableC12AttitudeStream(bool enabled)
{
    _ensureC12Socket();
    if (!_c12Socket) return;
    const QHostAddress host(_daggerC12Host());
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "_enableC12AttitudeStream: invalid host"
                                   << _daggerC12Host();
        return;
    }
    const QByteArray rateHex = QByteArray::number(enabled ? kC12AttitudeRateHz : 0, 16)
                                   .toUpper().rightJustified(2, '0');
    const QByteArray frame = _c12BuildFrame("UG", '2', 'w', "GAA", rateHex);
    if (_c12Socket->writeDatagram(frame, host, kC12ControlPort) != frame.size()) {
        qCWarning(VideoManagerLog) << "GAA enable send failed to" << host.toString();
        return;
    }
    _c12AttitudeStreamEnabled = enabled;
    qCInfo(VideoManagerLog) << "C12 attitude stream"
                            << (enabled ? "enabled" : "disabled")
                            << "rate" << (enabled ? kC12AttitudeRateHz : 0) << "Hz";
}

void VideoManager::_onC12AttitudeDatagram()
{
    if (!_c12Socket) return;
    while (_c12Socket->hasPendingDatagrams()) {
        QByteArray buf(int(_c12Socket->pendingDatagramSize()), Qt::Uninitialized);
        _c12Socket->readDatagram(buf.data(), buf.size());
        _processC12Frame(buf);
    }
}

void VideoManager::_processC12Frame(const QByteArray &frame)
{
    // Full GAC frame: 3 hdr + 2 addr + 1 len + 1 ctrl + 3 flag + 12 data + 2 chk = 24.
    if (frame.size() < 12) return;
    if (frame.at(0) != '#'
        || (frame.at(1) != 'T' && frame.at(1) != 't')
        || (frame.at(2) != 'P' && frame.at(2) != 'p')) return;

    bool lenOk = false;
    const int len = QByteArray(1, frame.at(5)).toInt(&lenOk, 16);
    if (!lenOk) return;
    // C12 TOP §2.2.3: length field counts data characters (=wire bytes), so the
    // data window is [dataStart, dataStart+len) and the 2-char checksum sits after.
    const int dataStart = 10;
    const int dataEnd   = dataStart + len;
    if (frame.size() < dataEnd + 2) return;

    int sum = 0;
    for (int i = 0; i < dataEnd; ++i) sum += static_cast<unsigned char>(frame.at(i));
    bool chkOk = false;
    const int recvChk = QByteArray(frame.constData() + dataEnd, 2).toInt(&chkOk, 16);
    if (!chkOk || (sum & 0xFF) != recvChk) {
        qCDebug(VideoManagerLog) << "C12 checksum mismatch, dropping" << frame;
        return;
    }

    if (frame.mid(7, 3) != "GAC" || len != 0xC) return;

    auto decode = [&](int offset) {
        bool ok = false;
        const uint16_t raw = frame.mid(dataStart + offset, 4).toUShort(&ok, 16);
        return ok ? static_cast<double>(static_cast<int16_t>(raw)) * 0.01 : 0.0;
    };
    const double yawDeg   = decode(0);
    const double pitchDeg = decode(4);
    const double rollDeg  = decode(8);

    _c12YawDeg = yawDeg;
    _c12PitchDeg = pitchDeg;
    _c12RollDeg = rollDeg;
    _c12AttitudeTimestampMs = QDateTime::currentMSecsSinceEpoch();
    emit c12AttitudeChanged();

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - _lastC12AttitudeReportMs < kC12AttitudeReportIntervalMs) return;
    _lastC12AttitudeReportMs = now;

    const QString line = QStringLiteral("C12 gimbal: yaw %1° pitch %2° roll %3°")
                             .arg(yawDeg,   0, 'f', 2)
                             .arg(pitchDeg, 0, 'f', 2)
                             .arg(rollDeg,  0, 'f', 2);
    qCDebug(VideoManagerLog) << line;
    if (_activeVehicle) {
        _activeVehicle->showStatusText(kSeverityInfo, line);
    }
}

// STRATUM: Skydroid AI V1.2.0 binary tracking protocol (UDP :1030).
//
// This is the protocol the Skydroid reference PC app uses to drive the C12's
// on-camera visual tracker. The gimbal-side ASCII #TPUG.SUM/GOT frames on :5000
// documented in the TOP protocol are *not* the tracker start path — field
// testing (and the reference app's source) confirmed only this AI binary path
// actually engages the tracker.
//
// Frame layout (little-endian multi-byte fields):
//   [0..1]   HEADER  = 0xAA, 0xA5
//   [2..3]   LEN     = payload length (u16 LE)
//   [4..5]   SEQ     = monotonic per-process counter (u16 LE)
//   [6]      CTRL    = 1 SET_REGION, 2 TRACK_CONTROL
//   [7..]    PAYLOAD
//   [tail-2] CRC16   = CRC-16/XMODEM over HEADER..end-of-PAYLOAD (u16 LE)
//   [tail]   TAIL    = 0xCD
//
// Payloads used here:
//   TRACK_CONTROL (10 bytes):  { u8 cmd, u8 video, u16 x0, u16 y0, u16 x1, u16 y1 }
//                              cmd 0 = release, 1 = enable, 3 = disable
//   SET_REGION    (9 bytes):   { u8 video, u16 x0, u16 y0, u16 x1, u16 y1 }
//                              coordinates on the 1280x720 original frame.
static constexpr quint16 kC12AiPort = 1030;

static uint16_t _c12AiCrc16(const uint8_t *data, int length)
{
    uint16_t crc = 0;
    for (int i = 0; i < length; ++i) {
        crc ^= uint16_t(data[i]) << 8;
        for (int b = 0; b < 8; ++b) {
            crc = (crc & 0x8000) ? uint16_t((crc << 1) ^ 0x1021) : uint16_t(crc << 1);
        }
    }
    return crc;
}

void VideoManager::_ensureC12AiSocket()
{
    if (_c12AiSocket) return;
    _c12AiSocket = new QUdpSocket(this);
    // Bind to :1030 so the camera's AI-result frames come back on the port
    // Python's reference app uses. If :1030 is unavailable (another instance,
    // another local app) fall back to an ephemeral port — send-only will still
    // work; only inbound AI-result parsing would be affected.
    if (!_c12AiSocket->bind(QHostAddress::AnyIPv4, kC12AiPort,
                            QAbstractSocket::ShareAddress | QAbstractSocket::ReuseAddressHint)) {
        qCInfo(VideoManagerLog) << "C12 AI socket: :1030 busy, using ephemeral port —"
                                << _c12AiSocket->errorString();
        (void) _c12AiSocket->bind(QHostAddress::AnyIPv4, 0);
    }
}

bool VideoManager::_sendC12AiPacket(quint8 control, const QByteArray &payload)
{
    _ensureC12AiSocket();
    if (!_c12AiSocket) return false;
    const QHostAddress host(_daggerC12Host());
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "_sendC12AiPacket: invalid C12 host" << _daggerC12Host();
        return false;
    }
    QByteArray frame;
    frame.reserve(2 + 2 + 2 + 1 + payload.size() + 2 + 1);
    frame.append(char(0xAA)); frame.append(char(0xA5));
    const quint16 len = quint16(payload.size());
    frame.append(char(len & 0xFF)); frame.append(char((len >> 8) & 0xFF));
    const quint16 seq = _c12AiSequence++;
    frame.append(char(seq & 0xFF)); frame.append(char((seq >> 8) & 0xFF));
    frame.append(char(control));
    frame.append(payload);
    const uint16_t crc = _c12AiCrc16(reinterpret_cast<const uint8_t *>(frame.constData()), frame.size());
    frame.append(char(crc & 0xFF)); frame.append(char((crc >> 8) & 0xFF));
    frame.append(char(0xCD));
    return _c12AiSocket->writeDatagram(frame, host, kC12AiPort) == frame.size();
}

bool VideoManager::sendC12TrackRegion(qreal x0, qreal y0, qreal x1, qreal y1, int videoSource)
{
    // Sort + clamp to the 1280x720 frame the C12 tracker expects.
    if (x0 > x1) qSwap(x0, x1);
    if (y0 > y1) qSwap(y0, y1);
    const int px0 = qBound(0, int(qRound(qBound(0.0, x0, 1.0) * 1279.0)), 1279);
    const int py0 = qBound(0, int(qRound(qBound(0.0, y0, 1.0) *  719.0)),  719);
    const int px1 = qBound(0, int(qRound(qBound(0.0, x1, 1.0) * 1279.0)), 1279);
    const int py1 = qBound(0, int(qRound(qBound(0.0, y1, 1.0) *  719.0)),  719);
    if (px1 - px0 < 8 || py1 - py0 < 8) {
        qCInfo(VideoManagerLog) << "sendC12TrackRegion: rejecting degenerate box"
                                << px0 << py0 << px1 << py1;
        return false;
    }
    const quint8 vid = (videoSource == 1) ? 1 : 0;

    // Enable the AI subsystem once per session — matches Python main.py's
    // start_region_track path (enable_ai then set_region).
    if (!_c12AiEnabled) {
        if (!setC12AiEnabled(true)) {
            qCWarning(VideoManagerLog) << "sendC12TrackRegion: enable_ai failed";
            return false;
        }
    }

    QByteArray regionPayload; regionPayload.reserve(9);
    regionPayload.append(char(vid));
    auto pushU16 = [&](int v) {
        regionPayload.append(char(v & 0xFF));
        regionPayload.append(char((v >> 8) & 0xFF));
    };
    pushU16(px0); pushU16(py0); pushU16(px1); pushU16(py1);
    const bool ok = _sendC12AiPacket(1 /*SET_REGION*/, regionPayload);
    qCInfo(VideoManagerLog).nospace()
        << "C12 track region video=" << vid
        << " (" << px0 << "," << py0 << ")->(" << px1 << "," << py1 << ") "
        << (ok ? "sent" : "FAILED");
    if (ok && !_c12TrackActive) {
        _c12TrackActive = true;
        emit c12TrackingActiveChanged();
    }
    return ok;
}

bool VideoManager::stopC12Track()
{
    return setC12AiEnabled(false);
}

bool VideoManager::setC12AiEnabled(bool enabled)
{
    bool releaseSent = true;
    if (!enabled) {
        const QByteArray releasePayload(10, char(0));
        releaseSent = _sendC12AiPacket(2, releasePayload);
        if (releaseSent && _c12TrackActive) {
            _c12TrackActive = false;
            emit c12TrackingActiveChanged();
        }
    }

    QByteArray controlPayload(10, char(0));
    controlPayload[0] = enabled ? char(1) : char(3);
    const bool controlSent = _sendC12AiPacket(2, controlPayload);
    if (!controlSent) {
        return false;
    }
    if (_c12AiEnabled != enabled) {
        _c12AiEnabled = enabled;
        emit c12AiEnabledChanged();
    }
    if (!enabled && _c12TrackActive) {
        _c12TrackActive = false;
        emit c12TrackingActiveChanged();
    }
    qCInfo(VideoManagerLog) << "C12 AI" << (enabled ? "enable" : "disable")
                           << "sent; release sent:" << releaseSent;
    return releaseSent && controlSent;
}

bool VideoManager::sendC12GimbalRate(int yaw, int pitch)
{
    _ensureC12Socket();
    if (!_c12Socket) return false;
    const QHostAddress host(_daggerC12Host());
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "sendC12GimbalRate: invalid C12 host" << _daggerC12Host();
        return false;
    }
    const int cy = qBound(-127, yaw,   127);
    const int cp = qBound(-127, pitch, 127);
    const QByteArray yawHex   = QByteArray::number(uint8_t(cy) & 0xFF, 16).toUpper().rightJustified(2, '0');
    const QByteArray pitchHex = QByteArray::number(uint8_t(cp) & 0xFF, 16).toUpper().rightJustified(2, '0');
    const QByteArray yawFrame   = _c12BuildFrame("UG", '2', 'w', "GSY", yawHex);
    const QByteArray pitchFrame = _c12BuildFrame("UG", '2', 'w', "GSP", pitchHex);
    const bool y = _c12Socket->writeDatagram(yawFrame,   host, kC12ControlPort) == yawFrame.size();
    const bool p = _c12Socket->writeDatagram(pitchFrame, host, kC12ControlPort) == pitchFrame.size();
    return y && p;
}

bool VideoManager::sendC12GimbalCombinedRate(int yaw, int pitch)
{
    _ensureC12Socket();
    if (!_c12Socket) return false;
    const QHostAddress host(_daggerC12Host());
    if (host.isNull()) return false;

    const int clampedYaw = qBound(-127, yaw, 127);
    const int clampedPitch = qBound(-127, pitch, 127);
    const QByteArray rates = QByteArray::number(uint8_t(clampedYaw) & 0xFF, 16).toUpper().rightJustified(2, '0')
                             + QByteArray::number(uint8_t(clampedPitch) & 0xFF, 16).toUpper().rightJustified(2, '0');
    const QByteArray frame = _c12BuildFrame("UG", '4', 'w', "GSM", rates);
    return _c12Socket->writeDatagram(frame, host, kC12ControlPort) == frame.size();
}

bool VideoManager::setC12GimbalAngles(double yawDegrees, double pitchDegrees, int speed)
{
    if (!std::isfinite(yawDegrees) || !std::isfinite(pitchDegrees)) return false;
    _ensureC12Socket();
    if (!_c12Socket) return false;
    const QHostAddress host(_daggerC12Host());
    if (host.isNull()) return false;

    const double boundedYaw = qBound(-90.0, yawDegrees, 90.0);
    const double boundedPitch = qBound(-90.0, pitchDegrees, 90.0);
    const int boundedSpeed = qBound(0, speed, 127);
    const auto signedAngleHex = [](double degrees) {
        const int angleHundredths = qBound(-9000, qRound(degrees * 100.0), 9000);
        return QByteArray::number(static_cast<uint16_t>(static_cast<int16_t>(angleHundredths)), 16)
            .toUpper().rightJustified(4, '0');
    };
    const QByteArray speedHex = QByteArray::number(boundedSpeed, 16).toUpper().rightJustified(2, '0');
    const QByteArray yawFrame = _c12BuildFrame("UG", '6', 'w', "GAY", signedAngleHex(boundedYaw) + speedHex);
    const QByteArray pitchFrame = _c12BuildFrame("UG", '6', 'w', "GAP", signedAngleHex(boundedPitch) + speedHex);
    const bool yawSent = _c12Socket->writeDatagram(yawFrame, host, kC12ControlPort) == yawFrame.size();
    const bool pitchSent = _c12Socket->writeDatagram(pitchFrame, host, kC12ControlPort) == pitchFrame.size();
    return yawSent && pitchSent;
}

bool VideoManager::moveRecordedFile(const QUrl &fromPath, const QUrl &toPath)
{
    const QString from = fromPath.isLocalFile() ? fromPath.toLocalFile() : fromPath.toString();
    const QString to   = toPath.isLocalFile()   ? toPath.toLocalFile()   : toPath.toString();
    if (from.isEmpty() || to.isEmpty()) {
        qCWarning(VideoManagerLog) << "moveRecordedFile: empty path" << from << "->" << to;
        return false;
    }
    if (!QFile::exists(from)) {
        qCWarning(VideoManagerLog) << "moveRecordedFile: source missing" << from;
        return false;
    }
    if (QFile::exists(to)) {
        (void) QFile::remove(to);
    }
    if (!QFile::rename(from, to)) {
        // Cross-volume rename fails on Windows; fall back to copy+remove.
        if (!QFile::copy(from, to)) {
            qCWarning(VideoManagerLog) << "moveRecordedFile: rename+copy failed" << from << "->" << to;
            return false;
        }
        (void) QFile::remove(from);
    }
    qCInfo(VideoManagerLog) << "moveRecordedFile:" << from << "->" << to;
    return true;
}

// STRATUM: SIYI A2 mini SDK v3 packet builder + UDP sender.
//
// Frame layout (little-endian multi-byte fields):
//   [0..1]   STX     = 0x55, 0x66
//   [2]      CTRL    = 0x01  (need-ACK; matches the reference SIYI SDK. Some A2 mini
//                             firmware silently drops CTRL=0x00 command frames.)
//   [3..4]   DATA_LEN
//   [5..6]   SEQ     = monotonic per-process counter (little-endian)
//   [7]      CMD_ID
//   [8..]    DATA
//   [tail]   CRC16 (poly 0x1021, init 0x0000, no reflection, no XOR-out;
//                  i.e. CRC-16/XMODEM) over bytes [0 .. end-of-DATA]
//
// A2 mini (single-axis tilt only) commands:
//   0x08 Center       DATA = { 0x01 }
//   0x07 Rate         DATA = { int8 yaw_speed, int8 pitch_speed }  (+pitch = UP)
//   0x0C Photo/Rec    DATA = { uint8 func_type }
//                     0 = take photo, 2 = start/stop record (toggle),
//                     3 = Lock mode, 4 = Follow mode, 5 = FPV mode
namespace {
uint16_t _siyiCrc16(const uint8_t *data, int length)
{
    uint16_t crc = 0x0000;
    for (int i = 0; i < length; ++i) {
        crc ^= static_cast<uint16_t>(data[i]) << 8;
        for (int b = 0; b < 8; ++b) {
            crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021)
                                 : static_cast<uint16_t>(crc << 1);
        }
    }
    return crc;
}

QByteArray _siyiPacket(uint8_t cmdId, const QByteArray &data, uint16_t seq)
{
    QByteArray p;
    p.reserve(10 + data.size());
    p.append(char(0x55)); p.append(char(0x66));
    p.append(char(0x01));                                       // CTRL: need ACK
    p.append(char(data.size() & 0xFF));
    p.append(char((data.size() >> 8) & 0xFF));
    p.append(char(seq & 0xFF));                                 // SEQ little-endian
    p.append(char((seq >> 8) & 0xFF));
    p.append(char(cmdId));
    p.append(data);
    const uint16_t crc = _siyiCrc16(reinterpret_cast<const uint8_t*>(p.constData()), p.size());
    p.append(char(crc & 0xFF));
    p.append(char((crc >> 8) & 0xFF));
    return p;
}
}

bool VideoManager::sendSiyiCameraAction(const QString &action)
{
    const QString a = action.trimmed().toLower();
    uint8_t cmdId = 0;
    QByteArray data;
    int repeat = 1;

    if (a == QLatin1String("center")) {
        cmdId = 0x08;
        data.append(char(0x01));
    } else if (a == QLatin1String("pitch-up")) {
        cmdId = 0x07;
        data.append(char(0));                                             // yaw
        data.append(static_cast<char>(static_cast<int8_t>(50)));          // +pitch = up
    } else if (a == QLatin1String("pitch-down")) {
        cmdId = 0x07;
        data.append(char(0));
        data.append(static_cast<char>(static_cast<int8_t>(-50)));         // -pitch = down
    } else if (a == QLatin1String("stop")) {
        cmdId = 0x07;
        data.append(char(0));
        data.append(char(0));
        repeat = 5;                                                       // survive UDP loss
    } else if (a == QLatin1String("capture")) {
        cmdId = 0x0C;
        data.append(char(0x00));
    } else if (a == QLatin1String("rec-toggle")) {
        cmdId = 0x0C;
        data.append(char(0x02));
    } else if (a == QLatin1String("mode-lock")) {
        cmdId = 0x0C;
        data.append(char(0x03));
    } else if (a == QLatin1String("mode-follow")) {
        cmdId = 0x0C;
        data.append(char(0x04));
    } else if (a == QLatin1String("mode-fpv")) {
        cmdId = 0x0C;
        data.append(char(0x05));
    } else if (a == QLatin1String("mode-cycle")) {                        // back-compat alias
        cmdId = 0x0C;
        data.append(char(0x03));
    } else {
        return false;
    }

    VideoSettings *vs = SettingsManager::instance()->videoSettings();
    const QString hostStr = vs ? vs->daggerCameraSdkHost()->rawValue().toString() : QString();
    const quint16 port    = vs ? static_cast<quint16>(vs->daggerCameraSdkPort()->rawValue().toUInt()) : quint16(0);
    if (hostStr.isEmpty() || port == 0) {
        qCWarning(VideoManagerLog) << "SIYI camera action" << a << "skipped: no host/port configured";
        return false;
    }
    const QHostAddress host(hostStr);
    if (host.isNull()) {
        qCWarning(VideoManagerLog) << "SIYI camera action" << a << "skipped: invalid host" << hostStr;
        return false;
    }

    // Persistent socket keeps the source port stable so the gimbal treats every packet
    // as part of the same client session. Monotonic SEQ so the gimbal does not de-dup
    // repeated stops.
    static QUdpSocket socket;
    static std::atomic<uint16_t> nextSeq{1};

    bool ok = true;
    for (int i = 0; i < repeat; ++i) {
        const QByteArray packet = _siyiPacket(cmdId, data, nextSeq.fetch_add(1));
        ok = (socket.writeDatagram(packet, host, port) == packet.size()) && ok;
    }
    return ok;
}

VideoManager *VideoManager::instance()
{
    return _videoManagerInstance();
}

void VideoManager::startGStreamerInit()
{
#ifdef QGC_GST_STREAMING
    if (_gstreamerDisabledForUnitTests) {
        _initState = InitState::GstReady;
        qCInfo(VideoManagerLog) << "GStreamer initialization disabled for unit tests";
        return;
    }

    if (_initState != InitState::NotStarted) {
        qCWarning(VideoManagerLog) << "GStreamer init already started";
        return;
    }

    _initState = InitState::Pending;

    GStreamer::prepareEnvironment();
    _gstInitFuture = QtConcurrent::run(&GStreamer::initialize);

    _gstInitFuture.then(this, [this](bool success) {
        _onGstInitComplete(success);
    }).onCanceled(this, [this] {
        _onGstInitComplete(false);
    });
#endif
}

bool VideoManager::waitForGStreamerInit(int timeoutMs)
{
#ifdef QGC_GST_STREAMING
    if (_gstreamerDisabledForUnitTests) {
        return true;
    }

    if (_initState == InitState::NotStarted) {
        startGStreamerInit();
    }

    switch (_initState) {
    case InitState::Failed:
        return false;
    case InitState::GstReady:
    case InitState::Running:
        return true;
    default:
        break;
    }

    if (!_gstInitFuture.isValid()) {
        qCCritical(VideoManagerLog) << "waitForGStreamerInit: no valid future";
        return false;
    }

    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QFutureWatcher<bool> watcher;
    (void) connect(&watcher, &QFutureWatcher<bool>::finished, &loop, &QEventLoop::quit);
    (void) connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);

    watcher.setFuture(_gstInitFuture);
    if (!watcher.isFinished()) {
        timer.start(timeoutMs);
        loop.exec();
    }

    if (!watcher.isFinished()) {
        qCCritical(VideoManagerLog) << "Timed out waiting for GStreamer init";
        return false;
    }

    const bool success = watcher.result();
    if (_initState == InitState::Pending || _initState == InitState::QmlReady) {
        _onGstInitComplete(success);
    }
    return _initState != InitState::Failed;
#else
    Q_UNUSED(timeoutMs);
    return true;
#endif
}

void VideoManager::init(QQuickWindow *mainWindow)
{
    if (_initialized) {
        qCDebug(VideoManagerLog) << "Video Manager already initialized";
        return;
    }

    if (!mainWindow) {
        qCCritical(VideoManagerLog) << "Failed To Init Video Manager - mainWindow is NULL";
        return;
    }
    _mainWindow = mainWindow;

#if defined(QGC_HAS_ANY_GPU_PATH)
    QGCRhiCapture::connectWindow(mainWindow);  // populate cached QRhi for GPU bridge handlers
#endif

    (void) connect(_videoSettings->videoSource(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
    (void) connect(_videoSettings->udpUrl(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
    (void) connect(_videoSettings->rtspUrl(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
    (void) connect(_videoSettings->tcpUrl(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
    (void) connect(_videoSettings->aspectRatio(), &Fact::rawValueChanged, this, &VideoManager::aspectRatioChanged);
    (void) connect(_videoSettings->lowLatencyMode(), &Fact::rawValueChanged, this, [this](const QVariant &value) { Q_UNUSED(value); _restartAllVideos(); });
    (void) connect(SettingsManager::instance()->appSettings()->gstDebugLevel(), &Fact::rawValueChanged, this, [](const QVariant &value) {
#ifdef QGC_GST_STREAMING
        GStreamer::setDebugLevel(value.toInt());
#else
        Q_UNUSED(value);
#endif
    });
    (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, &VideoManager::_setActiveVehicle);

    (void) connect(this, &VideoManager::autoStreamConfiguredChanged, this, &VideoManager::_videoSourceChanged);

    // STRATUM: bind the C12 attitude socket up front and enable the GAA stream
    // whenever the operator has selected the C12 (daggerCamera == 1). We also
    // re-send GAA on daggerCamera changes so the camera resumes streaming after
    // a mode swap or camera reboot.
    _ensureC12Socket();
    if (_videoSettings->daggerCamera()->rawValue().toInt() == 1) {
        _enableC12AttitudeStream(true);
    }
    (void) connect(_videoSettings->daggerCamera(), &Fact::rawValueChanged, this,
                   [this](const QVariant &value) {
                       _enableC12AttitudeStream(value.toInt() == 1);
                   });

#ifdef QGC_GST_STREAMING
    if (_initState == InitState::NotStarted) {
        startGStreamerInit();
    }
#endif

    _mainWindow->scheduleRenderJob(
        QRunnable::create([this] {
            QMetaObject::invokeMethod(this, &VideoManager::_initAfterQmlIsReady, Qt::QueuedConnection);
        }),
        QQuickWindow::AfterSynchronizingStage);

    _initialized = true;
}

void VideoManager::_initAfterQmlIsReady()
{
    if (!_mainWindow) {
        qCCritical(VideoManagerLog) << "_initAfterQmlIsReady called with NULL mainWindow";
        return;
    }

    qCDebug(VideoManagerLog) << "_initAfterQmlIsReady";

#ifdef QGC_GST_STREAMING
    switch (_initState) {
    case InitState::Pending:
        _initState = InitState::QmlReady;
        qCDebug(VideoManagerLog) << "QML ready, waiting for GStreamer";
        return;
    case InitState::GstReady:
        _initState = InitState::Running;
        qCDebug(VideoManagerLog) << "QML ready, GStreamer already done — creating receivers";
        break;
    case InitState::Failed:
        qCWarning(VideoManagerLog) << "QML ready but GStreamer init failed";
        return;
    default:
        qCWarning(VideoManagerLog) << "_initAfterQmlIsReady: unexpected state" << static_cast<int>(_initState);
        return;
    }
#endif
    _createVideoReceivers();
}

void VideoManager::_onGstInitComplete(bool success)
{
    if (!success) {
        _initState = InitState::Failed;
        qCCritical(VideoManagerLog) << "GStreamer initialization failed";
        return;
    }

#ifdef QGC_GST_STREAMING
    if (_videoSettings) {
        const auto decoderOption = static_cast<GStreamer::VideoDecoderOptions>(
            _videoSettings->forceVideoDecoder()->rawValue().toInt());
        GStreamer::setCodecPriorities(decoderOption);
    }
#endif

    switch (_initState) {
    case InitState::Pending:
        _initState = InitState::GstReady;
        qCDebug(VideoManagerLog) << "GStreamer ready, waiting for QML";
        return;
    case InitState::QmlReady:
        _initState = InitState::Running;
        qCDebug(VideoManagerLog) << "GStreamer ready, QML already done — creating receivers";
        _createVideoReceivers();
        return;
    default:
        qCWarning(VideoManagerLog) << "_onGstInitComplete: unexpected state" << static_cast<int>(_initState);
        return;
    }
}

void VideoManager::_createVideoReceivers()
{
#ifdef QGC_UNITTEST_BUILD
    if (_createVideoReceiversForTest) {
        _createVideoReceiversForTest();
        return;
    }
#endif
    static const QStringList videoStreamList = {
        "videoContent",
        "thermalVideo"
    };
    for (const QString &streamName : videoStreamList) {
        VideoReceiver *receiver = QGCCorePlugin::instance()->createVideoReceiver(this);
        if (!receiver) {
            continue;
        }
        receiver->setName(streamName);

        _initVideoReceiver(receiver, _mainWindow);
    }
}

void VideoManager::cleanup()
{
    for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
        QGCCorePlugin::instance()->releaseVideoSink(receiver->sink());
    }
}

void VideoManager::_cleanupOldVideos()
{
    if (!SettingsManager::instance()->videoSettings()->enableStorageLimit()->rawValue().toBool()) {
        return;
    }

    const QString savePath = SettingsManager::instance()->appSettings()->videoSavePath();
    QDir videoDir = QDir(savePath);
    videoDir.setFilter(QDir::Files | QDir::Readable | QDir::NoSymLinks | QDir::Writable);
    videoDir.setSorting(QDir::Time);

    QStringList nameFilters;
    for (size_t i = 0; i < std::size(kFileExtension); i++) {
        nameFilters << QStringLiteral("*.") + kFileExtension[i];
    }

    videoDir.setNameFilters(nameFilters);
    QFileInfoList vidList = videoDir.entryInfoList();
    if (vidList.isEmpty()) {
        return;
    }

    uint64_t total = 0;
    for (const QFileInfo &video : std::as_const(vidList)) {
        total += video.size();
    }

    const uint64_t maxSize = SettingsManager::instance()->videoSettings()->maxVideoSize()->rawValue().toUInt() * qPow(1024, 2);
    while ((total >= maxSize) && !vidList.isEmpty()) {
        const QFileInfo info = vidList.takeLast();
        total -= info.size();
        const QString path = info.filePath();
        qCDebug(VideoManagerLog) << "Removing old video file:" << path;
        (void) QFile::remove(path);
    }
}

void VideoManager::startRecording(const QString &videoFile)
{
    const VideoReceiver::FILE_FORMAT fileFormat = static_cast<VideoReceiver::FILE_FORMAT>(_videoSettings->recordingFormat()->rawValue().toInt());
    if (!VideoReceiver::isValidFileFormat(fileFormat)) {
        QGC::showAppMessage(tr("Invalid video format defined."));
        return;
    }

    _cleanupOldVideos();

    const QString savePath = SettingsManager::instance()->appSettings()->videoSavePath();
    if (savePath.isEmpty()) {
        QGC::showAppMessage(tr("Unabled to record video. Video save path must be specified in Settings."));
        return;
    }

    const QString videoFileUrl = videoFile.isEmpty() ? QDateTime::currentDateTime().toString("yyyy-MM-dd_hh.mm.ss") : videoFile;
    const QString ext = kFileExtension[fileFormat];

    const QString videoFileNameTemplate = savePath + "/" + videoFileUrl + ".%1" + ext;

    for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
        if (receiver->name() != QStringLiteral("videoContent")) {
            continue;
        }
        if (!receiver->started()) {
            qCDebug(VideoManagerLog) << "Video receiver is not ready.";
            continue;
        }
        const QString videoFileName = videoFileNameTemplate.arg("");
        receiver->startRecording(videoFileName, fileFormat);
    }
}

void VideoManager::stopRecording()
{
    for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
        if (receiver->name() != QStringLiteral("videoContent")) {
            continue;
        }
        receiver->stopRecording();
    }
}

void VideoManager::grabImage(const QString &imageFile)
{
    if (imageFile.isEmpty()) {
        _imageFile = SettingsManager::instance()->appSettings()->photoSavePath();
        _imageFile += QStringLiteral("/") + QDateTime::currentDateTime().toString("yyyy-MM-dd_hh.mm.ss.zzz") + QStringLiteral(".jpg");
    } else {
        _imageFile = imageFile;
    }

    emit imageFileChanged(_imageFile);

    for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
        receiver->takeScreenshot(_imageFile);
        // QSharedPointer<QQuickItemGrabResult> result = receiver->widget()->grabToImage(const QSize &targetSize = QSize())
    }
}

double VideoManager::aspectRatio() const
{
    for (VideoReceiver *receiver : _videoReceivers) {
        QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
        if (!receiver->isThermal() && pInfo && !pInfo->isThermal()) {
            return pInfo->aspectRatio();
        }
    }

    // FIXME: use _videoReceiver->videoSize() to calculate AR (if AR is not specified in the settings?)
    return _videoSettings->aspectRatio()->rawValue().toDouble();
}

double VideoManager::thermalAspectRatio() const
{
    for (VideoReceiver *receiver : _videoReceivers) {
        QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
        if (receiver->isThermal() && pInfo && pInfo->isThermal()) {
            return pInfo->aspectRatio();
        }
    }

    return 1.0;
}

double VideoManager::hfov() const
{
    for (VideoReceiver *receiver : _videoReceivers) {
        QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
        if (!receiver->isThermal() && pInfo && !pInfo->isThermal()) {
            return pInfo->hfov();
        }
    }

    return 1.0;
}

double VideoManager::thermalHfov() const
{
    for (VideoReceiver *receiver : _videoReceivers) {
        QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
        if (receiver->isThermal() && pInfo && pInfo->isThermal()) {
            return pInfo->hfov();
        }
    }

    return _videoSettings->aspectRatio()->rawValue().toDouble();
}

bool VideoManager::hasThermal() const
{
    for (VideoReceiver *receiver : _videoReceivers) {
        QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
        if (receiver->isThermal() && pInfo && pInfo->isThermal()) {
            return true;
        }
    }

    return false;
}

bool VideoManager::hasVideo() const
{
    return (_videoSettings->streamEnabled()->rawValue().toBool() && _videoSettings->streamConfigured());
}

bool VideoManager::isUvc() const
{
    return (!_uvcVideoSourceID.isEmpty() && uvcEnabled() && hasVideo());
}

bool VideoManager::gstreamerEnabled()
{
#ifdef QGC_GST_STREAMING
    return true;
#else
    return false;
#endif
}

bool VideoManager::uvcEnabled()
{
    return UVCReceiver::enabled();
}

bool VideoManager::qtmultimediaEnabled()
{
    return QtMultimediaReceiver::enabled();
}

void VideoManager::setfullScreen(bool on)
{
    if (on) {
        if (!_activeVehicle || _activeVehicle->vehicleLinkManager()->communicationLost()) {
            on = false;
        }
    }

    if (on != _fullScreen) {
        _fullScreen = on;
        emit fullScreenChanged();
    }
}

bool VideoManager::isStreamSource() const
{
    static const QStringList videoSourceList = {
        VideoSettings::videoSourceUDPH264,
        VideoSettings::videoSourceUDPH265,
        VideoSettings::videoSourceRTSP,
        VideoSettings::videoSourceTCP,
        VideoSettings::videoSourceMPEGTS,
        VideoSettings::videoSource3DRSolo,
        VideoSettings::videoSourceParrotDiscovery,
        VideoSettings::videoSourceYuneecMantisG,
        VideoSettings::videoSourceHerelinkAirUnit,
        VideoSettings::videoSourceHerelinkHotspot,
    };
    const QString videoSource = _videoSettings->videoSource()->rawValue().toString();
    return (videoSourceList.contains(videoSource) || autoStreamConfigured());
}

void VideoManager::_videoSourceChanged()
{
    bool changed = false;
    if (_activeVehicle) {
        QGCCameraManager* camMgr = _activeVehicle->cameraManager();
        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            QGCVideoStreamInfo* info = nullptr;
            if (receiver->isThermal()) {
                info = camMgr ? camMgr->thermalStreamInstance() : nullptr;
            } else {
                info = camMgr ? camMgr->currentStreamInstance() : nullptr;
            }
            receiver->setVideoStreamInfo(info);
            changed |= _updateSettings(receiver);
        }
    } else {
        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            receiver->setVideoStreamInfo(nullptr);
            changed |= _updateSettings(receiver);
        }
    }

    if (changed) {
        emit hasVideoChanged();
        emit isStreamSourceChanged();
        emit isAutoStreamChanged();

        if (hasVideo()) {
            _restartAllVideos();
        } else {
            stopVideo();
        }

        qCDebug(VideoManagerLog) << "New Video Source:" << _videoSettings->videoSource()->rawValue().toString();
    }
}

bool VideoManager::_updateUVC(VideoReceiver * /*receiver*/)
{
    bool result = false;

    const QString oldUvcVideoSrcID = _uvcVideoSourceID;

    if (!uvcEnabled() || !hasVideo() || isStreamSource()) {
        _uvcVideoSourceID = QString();
    } else {
        _uvcVideoSourceID = UVCReceiver::getSourceId();
    }

    if (oldUvcVideoSrcID != _uvcVideoSourceID) {
        qCDebug(VideoManagerLog) << "UVC changed from [" << oldUvcVideoSrcID << "] to [" << _uvcVideoSourceID << "]";
        if (!_uvcVideoSourceID.isEmpty()) {
            UVCReceiver::checkPermission();
        }
        result = true;
        emit uvcVideoSourceIDChanged();
        emit isUvcChanged();
    }

    return result;
}

bool VideoManager::autoStreamConfigured() const
{
    for (VideoReceiver *receiver : _videoReceivers) {
        QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
        if (!receiver->isThermal() && pInfo && !pInfo->isThermal()) {
            return !pInfo->uri().isEmpty();
        }
    }

    return false;
}

bool VideoManager::_updateAutoStream(VideoReceiver *receiver)
{
    const QGCVideoStreamInfo *pInfo = receiver->videoStreamInfo();
    if (!pInfo) {
        return false;
    }

    qCDebug(VideoManagerLog) << QString("Configure stream (%1):").arg(receiver->name()) << pInfo->uri();

    QString source, url;
    switch (pInfo->type()) {
    case VIDEO_STREAM_TYPE_RTSP:
        source = VideoSettings::videoSourceRTSP;
        url = pInfo->uri();
        if (source == VideoSettings::videoSourceRTSP) {
            _videoSettings->rtspUrl()->setRawValue(url);
        }
        break;
    case VIDEO_STREAM_TYPE_TCP_MPEG:
        source = VideoSettings::videoSourceTCP;
        url = pInfo->uri();
        break;
    case VIDEO_STREAM_TYPE_RTPUDP:
        if (pInfo->encoding() == VIDEO_STREAM_ENCODING_H265) {
            source = VideoSettings::videoSourceUDPH265;
            url = pInfo->uri().contains("udp265://") ? pInfo->uri() : QStringLiteral("udp265://0.0.0.0:%1").arg(pInfo->uri());
        } else {
            source = VideoSettings::videoSourceUDPH264;
            url = pInfo->uri().contains("udp://") ? pInfo->uri() : QStringLiteral("udp://0.0.0.0:%1").arg(pInfo->uri());
        }
        break;
    case VIDEO_STREAM_TYPE_MPEG_TS:
        source = VideoSettings::videoSourceMPEGTS;
        url = pInfo->uri().contains("mpegts://") ? pInfo->uri() : QStringLiteral("mpegts://0.0.0.0:%1").arg(pInfo->uri());
        break;
    default:
        qCWarning(VideoManagerLog) << "Unknown VIDEO_STREAM_TYPE";
        source = VideoSettings::videoSourceNoVideo;
        url = pInfo->uri();
        break;
    }

    const bool settingsChanged = _updateVideoUri(receiver, url);
    if (settingsChanged) {
        if (!receiver->isThermal()) {
            _videoSettings->videoSource()->setRawValue(source);
        }

        emit autoStreamConfiguredChanged();
    }

    return settingsChanged;
}

bool VideoManager::_updateVideoUri(VideoReceiver *receiver, const QString &uri)
{
    if (!receiver) {
        qCDebug(VideoManagerLog) << "VideoReceiver is NULL";
        return false;
    }

    if ((uri == receiver->uri()) && !receiver->uri().isNull()) {
        return false;
    }

    qCDebug(VideoManagerLog) << "New Video URI" << uri;

    receiver->setUri(uri);

    return true;
}

bool VideoManager::_updateSettings(VideoReceiver *receiver)
{
    if (!receiver) {
        qCDebug(VideoManagerLog) << "VideoReceiver is NULL";
        return false;
    }

    bool settingsChanged = false;

    const bool lowLatency = _videoSettings->lowLatencyMode()->rawValue().toBool();
    if (lowLatency != receiver->lowLatency()) {
        receiver->setLowLatency(lowLatency);
        settingsChanged = true;
    }

    if (receiver->isThermal()) {
        return settingsChanged;
    }

    settingsChanged |= _updateUVC(receiver);
    settingsChanged |= _updateAutoStream(receiver);

    const QString source = _videoSettings->videoSource()->rawValue().toString();
    if (source == VideoSettings::videoSourceUDPH264) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp://%1").arg(_videoSettings->udpUrl()->rawValue().toString()));
    } else if (source == VideoSettings::videoSourceUDPH265) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp265://%1").arg(_videoSettings->udpUrl()->rawValue().toString()));
    } else if (source == VideoSettings::videoSourceMPEGTS) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("mpegts://%1").arg(_videoSettings->udpUrl()->rawValue().toString()));
    } else if (source == VideoSettings::videoSourceRTSP) {
        settingsChanged |= _updateVideoUri(receiver, _videoSettings->rtspUrl()->rawValue().toString());
    } else if (source == VideoSettings::videoSourceTCP) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("tcp://%1").arg(_videoSettings->tcpUrl()->rawValue().toString()));
    } else if (source == VideoSettings::videoSource3DRSolo) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp://0.0.0.0:5600"));
    } else if (source == VideoSettings::videoSourceParrotDiscovery) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp://0.0.0.0:8888"));
    } else if (source == VideoSettings::videoSourceYuneecMantisG) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("rtsp://192.168.42.1:554/live"));
    } else if (source == VideoSettings::videoSourceHerelinkAirUnit) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("rtsp://192.168.0.10:8554/H264Video"));
    } else if (source == VideoSettings::videoSourceHerelinkHotspot) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("rtsp://192.168.43.1:8554/fpv_stream"));
    } else if ((source == VideoSettings::videoDisabled) || (source == VideoSettings::videoSourceNoVideo)) {
        settingsChanged |= _updateVideoUri(receiver, QString());
    } else {
        settingsChanged |= _updateVideoUri(receiver, QString());
        if (!isUvc()) {
            qCCritical(VideoManagerLog) << "Video source URI \"" << source << "\" is not supported. Please add support!";
        }
    }

    return settingsChanged;
}

void VideoManager::_setActiveVehicle(Vehicle *vehicle)
{
    qCDebug(VideoManagerLog) << Q_FUNC_INFO << "new vehicle" << vehicle << "old active vehicle" << _activeVehicle;

    if (_activeVehicle) {
        (void) disconnect(_activeVehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged, this, &VideoManager::_communicationLostChanged);
        auto cameraManager = _activeVehicle->cameraManager();
        if (cameraManager) {
            MavlinkCameraControlInterface *pCamera = cameraManager->currentCameraInstance();
            if (pCamera) {
                pCamera->stopStream();
            }
            (void) disconnect(cameraManager, &QGCCameraManager::streamChanged, this, &VideoManager::_videoSourceChanged);
        }

        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            // disconnect(receiver->videoStreamInfo(), &QGCVideoStreamInfo::infoChanged, ))
            receiver->setVideoStreamInfo(nullptr);
        }
    }

    _activeVehicle = vehicle;
    if (_activeVehicle) {
        (void) connect(_activeVehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged, this, &VideoManager::_communicationLostChanged);
        if (_activeVehicle->cameraManager()) {
            (void) connect(_activeVehicle->cameraManager(), &QGCCameraManager::streamChanged, this, &VideoManager::_videoSourceChanged);
            MavlinkCameraControlInterface *pCamera = _activeVehicle->cameraManager()->currentCameraInstance();
            if (pCamera) {
                pCamera->resumeStream();
            }
        }

        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            if (_activeVehicle->cameraManager()) {
                if (receiver->isThermal()) {
                    receiver->setVideoStreamInfo(_activeVehicle->cameraManager()->thermalStreamInstance());
                } else {
                    receiver->setVideoStreamInfo(_activeVehicle->cameraManager()->currentStreamInstance());
                }
            } else {
                receiver->setVideoStreamInfo(nullptr);
            }
            // connect(receiver->videoStreamInfo(), &QGCVideoStreamInfo::infoChanged, ))
        }
    } else {
        setfullScreen(false);
    }
}

void VideoManager::_communicationLostChanged(bool connectionLost)
{
    if (connectionLost) {
        setfullScreen(false);
    }
}

void VideoManager::_restartAllVideos()
{
    for (VideoReceiver *videoReceiver : std::as_const(_videoReceivers)) {
        _restartVideo(videoReceiver);
    }
}

void VideoManager::_restartVideo(VideoReceiver *receiver)
{
    if (!receiver) {
        qCDebug(VideoManagerLog) << "VideoReceiver is NULL";
        return;
    }

    qCDebug(VideoManagerLog) << "Restart video receiver" << receiver->name();

    if (receiver->started()) {
        _stopReceiver(receiver);
        // onStopComplete Signal Will Restart It
    } else {
        _startReceiver(receiver);
    }
}

void VideoManager::_stopReceiver(VideoReceiver *receiver)
{
    if (!receiver) {
        qCDebug(VideoManagerLog) << "VideoReceiver is NULL";
        return;
    }

    if (receiver->started()) {
        receiver->stop();
    }
}

void VideoManager::stopVideo()
{
    for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
        _stopReceiver(receiver);
    }
}

void VideoManager::_startReceiver(VideoReceiver *receiver)
{
    if (!receiver) {
        qCDebug(VideoManagerLog) << "VideoReceiver is NULL";
        return;
    }

    if (receiver->started()) {
        qCDebug(VideoManagerLog) << "VideoReceiver is already started" << receiver->name();
        return;
    }

    if (receiver->uri().isEmpty()) {
        qCDebug(VideoManagerLog) << "VideoUri is NULL" << receiver->name();
        return;
    }

    const QString source = _videoSettings->videoSource()->rawValue().toString();
    /* The gstreamer rtsp source will switch to tcp if udp is not available after 5 seconds.
       So we should allow for some negotiation time for rtsp */

    const uint32_t timeout = ((source == VideoSettings::videoSourceRTSP) ? _videoSettings->rtspTimeout()->rawValue().toUInt() : 3);

    receiver->start(timeout);
}

void VideoManager::_initVideoReceiver(VideoReceiver *receiver, QQuickWindow *window)
{
    if (_videoReceivers.contains(receiver)) {
        qCWarning(VideoManagerLog) << "Receiver already initialized";
    }

    QQuickItem *widget = window->findChild<QQuickItem*>(receiver->name());
    if (!widget) {
        qCCritical(VideoManagerLog) << "stream widget not found" << receiver->name();
    }
    receiver->setWidget(widget);

    void *sink = QGCCorePlugin::instance()->createVideoSink(receiver->widget(), receiver);
    if (!sink) {
        qCCritical(VideoManagerLog) << "createVideoSink() failed" << receiver->name();
    }
    receiver->setSink(sink);

#ifdef QGC_GST_STREAMING
    if (sink && widget) {
        auto *videoOutput = qobject_cast<QQuickVideoOutput *>(widget);
        if (videoOutput) {
            QVideoSink *videoSink = videoOutput->videoSink();
            if (!GStreamer::setupAppSinkAdapter(sink, videoSink, receiver)) {
                qCWarning(VideoManagerLog) << "setupAppSinkAdapter failed" << receiver->name();
            }
            // Visibility gate: drop frames at the appsink while the host window is hidden
            // or minimized. The decoder still runs (cheap with HW accel) but render-thread
            // and copy work disappears. Connector handles late window attachment via
            // QQuickItem::windowChanged.
            auto applyVisibility = [receiver](QWindow *win) {
                if (!win) return;
                const QWindow::Visibility v = win->visibility();
                const bool active = (v != QWindow::Hidden && v != QWindow::Minimized);
                GStreamer::setAppSinkAdaptersActive(receiver, active);
            };
            // Track the previous connection so windowChanged can drop it before wiring the
            // new window. Without this, an old hidden/minimized window keeps gating the
            // live receiver after the video output reparents to a new window.
            auto prevConn = std::make_shared<QMetaObject::Connection>();
            auto wireWindow = [receiver, applyVisibility, prevConn](QQuickWindow *qw) {
                if (*prevConn) {
                    QObject::disconnect(*prevConn);
                    *prevConn = QMetaObject::Connection{};
                }
                if (!qw) return;
                applyVisibility(qw);
                *prevConn = QObject::connect(qw, &QWindow::visibilityChanged, receiver,
                    [applyVisibility, qw](QWindow::Visibility) { applyVisibility(qw); });
            };
            if (QQuickWindow *qw = videoOutput->window()) wireWindow(qw);
            QObject::connect(videoOutput, &QQuickVideoOutput::windowChanged, receiver, wireWindow);
        } else {
            qCWarning(VideoManagerLog) << "Widget is not a VideoOutput, cannot connect appsink" << receiver->name();
        }
    }
#endif

    (void) connect(receiver, &VideoReceiver::onStartComplete, this, [this, receiver](VideoReceiver::STATUS status) {
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "Start complete, status:" << status;
        switch (status) {
        case VideoReceiver::STATUS_OK:
            receiver->setStarted(true);
            if (receiver->sink()) {
                receiver->startDecoding(receiver->sink());
            }
            break;
        case VideoReceiver::STATUS_INVALID_URL:
        case VideoReceiver::STATUS_INVALID_STATE:
            break;
        default:
            _restartVideo(receiver);
            break;
        }
    });

    (void) connect(receiver, &VideoReceiver::onStopComplete, this, [this, receiver](VideoReceiver::STATUS status) {
        qCDebug(VideoManagerLog) << "Stop complete" << receiver->name() << receiver->uri()  << ", status:" << status;
        receiver->setStarted(false);
        if (status == VideoReceiver::STATUS_INVALID_URL) {
            qCDebug(VideoManagerLog) << "Invalid video URL. Not restarting";
        } else {
            QTimer::singleShot(1000, receiver, [this, receiver]() {
                qCDebug(VideoManagerLog) << "Restarting video receiver" << receiver->name() << receiver->uri();
                _startReceiver(receiver);
            });
        }
    });

    (void) connect(receiver, &VideoReceiver::streamingChanged, this, [this, receiver](bool active) {
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "streaming changed, active:" << (active ? "yes" : "no");
        if (!receiver->isThermal()) {
            _streaming = active;
            emit streamingChanged();
        }
    });

    (void) connect(receiver, &VideoReceiver::decodingChanged, this, [this, receiver](bool active) {
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "decoding changed, active:" << (active ? "yes" : "no");
        if (!receiver->isThermal()) {
            _decoding = active;
            emit decodingChanged();
        }
    });

    (void) connect(receiver, &VideoReceiver::recordingChanged, this, [this, receiver](bool active) {
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "recording changed, active:" << (active ? "yes" : "no");
        if (receiver->name() == QStringLiteral("videoContent")) {
            _recording = active;
            if (!active) {
                _subtitleWriter->stopCapturingTelemetry();
            }
            emit recordingChanged(_recording);
        }
    });

    (void) connect(receiver, &VideoReceiver::recordingStarted, this, [this, receiver](const QString &filename) {
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "recording started";
        if (receiver->name() == QStringLiteral("videoContent")) {
            _subtitleWriter->startCapturingTelemetry(filename, videoSize());
            // STRATUM: re-emit so QML (FlyView REC button) can remember the temp
            // filename and, on stop, prompt the operator for a save-as destination.
            emit recordingStarted(filename);
        }
    });

    (void) connect(receiver, &VideoReceiver::videoSizeChanged, this, [this, receiver](QSize size) {
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "resized. New resolution:" << size.width() << "x" << size.height();
        if (!receiver->isThermal()) {
            _videoSize = size;
            emit videoSizeChanged();
        }
    });

    (void) connect(receiver, &VideoReceiver::onTakeScreenshotComplete, this, [receiver](VideoReceiver::STATUS status) {
        if (status == VideoReceiver::STATUS_OK) {
            qCDebug(VideoManagerLog) << "Video" << receiver->name() << "screenshot taken";
        } else {
            qCWarning(VideoManagerLog) << "Video" << receiver->name() << "screenshot failed";
        }
    });

    (void) connect(receiver, &VideoReceiver::videoStreamInfoChanged, this, [this, receiver]() {
        const QGCVideoStreamInfo *videoStreamInfo = receiver->videoStreamInfo();
        qCDebug(VideoManagerLog) << "Video" << receiver->name() << "stream info:" << (videoStreamInfo ? "received" : "lost");

        (void) _updateAutoStream(receiver);
    });

    (void) _updateSettings(receiver);

    _videoReceivers.append(receiver);

    if (hasVideo()) {
        _startReceiver(receiver);
    }
}

void VideoManager::startVideo()
{
    qCDebug(VideoManagerLog) << "startVideo";

    if (!hasVideo()) {
        qCDebug(VideoManagerLog) << "Stream not enabled/configured";
        return;
    }

    _restartAllVideos();
}
