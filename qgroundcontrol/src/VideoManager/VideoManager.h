#pragma once

#include <QtCore/QFuture>
#include <QtCore/QPromise>
#include <QtCore/QObject>
#include <QtCore/QSize>
#include <QtQmlIntegration/QtQmlIntegration>

#include <QtCore/QString>

#include <functional>
#include <memory>

class QQuickWindow;
class SubtitleWriter;
class Vehicle;
class VideoReceiver;
class VideoSettings;
class QUdpSocket;

class VideoManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
    Q_MOC_INCLUDE("Vehicle.h")

    Q_PROPERTY(bool     gstreamerEnabled        READ gstreamerEnabled                           CONSTANT)
    Q_PROPERTY(bool     qtmultimediaEnabled     READ qtmultimediaEnabled                        CONSTANT)
    Q_PROPERTY(bool     uvcEnabled              READ uvcEnabled                                 CONSTANT)
    Q_PROPERTY(bool     autoStreamConfigured    READ autoStreamConfigured                       NOTIFY autoStreamConfiguredChanged)
    Q_PROPERTY(bool     decoding                READ decoding                                   NOTIFY decodingChanged)
    Q_PROPERTY(bool     fullScreen              READ fullScreen             WRITE setfullScreen NOTIFY fullScreenChanged)
    Q_PROPERTY(bool     hasThermal              READ hasThermal                                 NOTIFY decodingChanged)
    Q_PROPERTY(bool     hasVideo                READ hasVideo                                   NOTIFY hasVideoChanged)
    Q_PROPERTY(bool     isStreamSource          READ isStreamSource                             NOTIFY isStreamSourceChanged)
    Q_PROPERTY(bool     isUvc                   READ isUvc                                      NOTIFY isUvcChanged)
    Q_PROPERTY(bool     recording               READ recording                                  NOTIFY recordingChanged)
    Q_PROPERTY(bool     streaming               READ streaming                                  NOTIFY streamingChanged)
    Q_PROPERTY(double   aspectRatio             READ aspectRatio                                NOTIFY aspectRatioChanged)
    Q_PROPERTY(double   hfov                    READ hfov                                       NOTIFY aspectRatioChanged)
    Q_PROPERTY(double   thermalAspectRatio      READ thermalAspectRatio                         NOTIFY aspectRatioChanged)
    Q_PROPERTY(double   thermalHfov             READ thermalHfov                                NOTIFY aspectRatioChanged)
    Q_PROPERTY(QSize    videoSize               READ videoSize                                  NOTIFY videoSizeChanged)
    Q_PROPERTY(QString  imageFile               READ imageFile                                  NOTIFY imageFileChanged)
    Q_PROPERTY(QString  uvcVideoSourceID        READ uvcVideoSourceID                           NOTIFY uvcVideoSourceIDChanged)

    friend class VideoManagerInitTest;

public:
    explicit VideoManager(QObject *parent = nullptr);
    ~VideoManager();

    static VideoManager *instance();

    Q_INVOKABLE void grabImage(const QString &imageFile = QString());
    Q_INVOKABLE void startRecording(const QString &videoFile = QString());
    Q_INVOKABLE void startVideo();
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void stopVideo();
    Q_INVOKABLE bool sendCameraAction(const QString &action);
    Q_INVOKABLE bool sendCameraTrackPoint(int x, int y);
    // STRATUM: start C12 in-camera tracking on a screen region. Coordinates are
    // normalized 0..1 (letterbox-corrected by the caller). videoSource: 0=visible,
    // 1=IR. Uses the Skydroid AI V1.2.0 binary protocol on UDP :1030 (SET_REGION),
    // preceded by TRACK_CONTROL/enable_ai the first time. This is the sequence the
    // Skydroid reference PC app uses and the only one confirmed to actually engage
    // the on-camera tracker.
    Q_INVOKABLE bool sendC12TrackRegion(qreal x0, qreal y0, qreal x1, qreal y1, int videoSource = 0);
    // STRATUM: stop C12 in-camera tracking (AI V1.2.0 release + disable).
    Q_INVOKABLE bool stopC12Track();
    Q_INVOKABLE bool sendSiyiCameraAction(const QString &action);
    // STRATUM: reprogram the C12 gimbal's IP via Skydroid/YunZhuo "IPV" command.
    // Sends to the current stored IP; on success rewrites videoSettings.daggerC12Host
    // so subsequent commands go to the new address.
    Q_INVOKABLE bool setC12CameraIp(const QString &newIp);
    // STRATUM: query the C12 gimbal for its actual IP with the Skydroid "rIPV" command.
    // Returns the IPv4 string on success or an empty string on failure/timeout.
    Q_INVOKABLE QString readC12CameraIp(int timeoutMs = 1000);

    void init(QQuickWindow *mainWindow);
    void startGStreamerInit();
    bool waitForGStreamerInit(int timeoutMs = 60000);
    void cleanup();
    bool autoStreamConfigured() const;
    bool decoding() const { return _decoding; }
    bool fullScreen() const { return _fullScreen; }
    bool hasThermal() const;
    bool hasVideo() const;
    bool isStreamSource() const;
    bool isUvc() const;
    bool recording() const { return _recording; }
    bool streaming() const { return _streaming; }
    double aspectRatio() const;
    double hfov() const;
    double thermalAspectRatio() const;
    double thermalHfov() const;
    QSize videoSize() const { return _videoSize; }
    QString imageFile() const { return _imageFile; }
    QString uvcVideoSourceID() const { return _uvcVideoSourceID; }
    void setfullScreen(bool on);
    static bool gstreamerEnabled();
    static bool qtmultimediaEnabled();
    static bool uvcEnabled();

signals:
    void aspectRatioChanged();
    void autoStreamConfiguredChanged();
    void decodingChanged();
    void fullScreenChanged();
    void hasVideoChanged();
    void imageFileChanged(const QString &filename);
    void isAutoStreamChanged();
    void isStreamSourceChanged();
    void isUvcChanged();
    void recordingChanged(bool recording);
    void recordingStarted(const QString &filename);
    void streamingChanged();
    void uvcVideoSourceIDChanged();
    void videoSizeChanged();

private slots:
    void _communicationLostChanged(bool communicationLost);
    void _setActiveVehicle(Vehicle *vehicle);
    void _videoSourceChanged();
    // STRATUM: C12 gimbal attitude (GAC) stream reader — parses angles into the
    // vehicle-messages drawer at ~1 Hz. Bound to the same persistent UDP socket
    // that sends the GAA enable to the camera.
    void _onC12AttitudeDatagram();

private:
    enum class InitState : uint8_t {
        NotStarted,
        Pending,
        GstReady,
        QmlReady,
        Running,
        Failed
    };

    static bool _shouldSkipGStreamerForUnitTests();
    void _initAfterQmlIsReady();
    void _onGstInitComplete(bool success);
    void _createVideoReceivers();
    void _initVideoReceiver(VideoReceiver *receiver, QQuickWindow *window);
    bool _updateAutoStream(VideoReceiver *receiver);
    bool _updateUVC(VideoReceiver *receiver);
    bool _updateSettings(VideoReceiver *receiver);
    bool _updateVideoUri(VideoReceiver *receiver, const QString &uri);
    void _restartAllVideos();
    void _restartVideo(VideoReceiver *receiver);
    void _startReceiver(VideoReceiver *receiver);
    void _stopReceiver(VideoReceiver *receiver);
    static void _cleanupOldVideos();

    void _ensureC12Socket();
    void _enableC12AttitudeStream(bool enabled);
    void _processC12Frame(const QByteArray &frame);

    void _ensureC12AiSocket();
    bool _sendC12AiPacket(quint8 control, const QByteArray &payload);

    QList<VideoReceiver*> _videoReceivers;
    SubtitleWriter *_subtitleWriter = nullptr;
    VideoSettings *_videoSettings = nullptr;
    QQuickWindow *_mainWindow = nullptr;
    Vehicle *_activeVehicle = nullptr;

    // STRATUM: persistent UDP socket used to enable + receive C12 gimbal-attitude
    // frames (GAA/GAC). Bound to a local ephemeral port; the camera replies to
    // whichever source port sent the enable, so we keep this socket alive for
    // the life of the app. Rate-limited push to the vehicle-messages drawer.
    QUdpSocket *_c12Socket = nullptr;
    qint64 _lastC12AttitudeReportMs = 0;
    bool _c12AttitudeStreamEnabled = false;

    // STRATUM: persistent UDP socket for the Skydroid AI V1.2.0 binary tracking
    // protocol (UDP :1030). Bound locally so we can eventually parse the AI result
    // frames the camera streams back. Sequence counter is monotonic per-process.
    QUdpSocket *_c12AiSocket = nullptr;
    quint16 _c12AiSequence = 0;
    bool _c12AiEnabled = false;

    InitState _initState = InitState::NotStarted;
    QFuture<bool> _gstInitFuture;
#if defined(QGC_GST_STREAMING) && defined(Q_OS_ANDROID)
#endif
    bool _initialized = false;
    bool _gstreamerDisabledForUnitTests = false;
    bool _fullScreen = false;

    QAtomicInteger<bool> _decoding = false;
    QAtomicInteger<bool> _recording = false;
    QAtomicInteger<bool> _streaming = false;
    QSize _videoSize;
    QString _imageFile;
    QString _uvcVideoSourceID;

#ifdef QGC_UNITTEST_BUILD
    std::function<void()> _createVideoReceiversForTest;
#endif
};
