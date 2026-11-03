#pragma once

#include <QtQmlIntegration/QtQmlIntegration>

#include "SettingsGroup.h"

class VideoSettings : public SettingsGroup
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
public:
    VideoSettings(QObject* parent = nullptr);
    DEFINE_SETTING_NAME_GROUP()

    DEFINE_SETTINGFACT(videoSource)
    DEFINE_SETTINGFACT(udpUrl)
    DEFINE_SETTINGFACT(tcpUrl)
    DEFINE_SETTINGFACT(rtspUrl)
    DEFINE_SETTINGFACT(tvRtspUrl)
    DEFINE_SETTINGFACT(irRtspUrl)
    DEFINE_SETTINGFACT(daggerRtspUrl)   // STRATUM: Dagger A2 mini feed URL
    DEFINE_SETTINGFACT(daggerC12TvRtspUrl)  // STRATUM: Dagger C12 (TV) feed URL
    DEFINE_SETTINGFACT(daggerC12IrRtspUrl)  // STRATUM: Dagger C12 (IR) feed URL
    DEFINE_SETTINGFACT(daggerCamera)        // STRATUM: 0 = A2 mini, 1 = C12
    DEFINE_SETTINGFACT(daggerCameraSdkHost) // STRATUM: A2 mini SDK IP
    DEFINE_SETTINGFACT(daggerCameraSdkPort) // STRATUM: A2 mini SDK UDP port
    DEFINE_SETTINGFACT(daggerC12Host)       // STRATUM: current C12 gimbal IP
    DEFINE_SETTINGFACT(daggerDeviceKey)     // STRATUM: DIP V2 AES-128 key (32 hex chars) for camera auto-provisioning
    DEFINE_SETTINGFACT(deviceRegistry)      // STRATUM: JSON array of {serial, name} device entries (DIP V2 registry)
    DEFINE_SETTINGFACT(aspectRatio)
    DEFINE_SETTINGFACT(videoFit)
    DEFINE_SETTINGFACT(gridLines)
    DEFINE_SETTINGFACT(showRecControl)
    DEFINE_SETTINGFACT(recordingFormat)
    DEFINE_SETTINGFACT(maxVideoSize)
    DEFINE_SETTINGFACT(enableStorageLimit)
    DEFINE_SETTINGFACT(rtspTimeout)
    DEFINE_SETTINGFACT(streamEnabled)
    DEFINE_SETTINGFACT(disableWhenDisarmed)
    DEFINE_SETTINGFACT(lowLatencyMode)
    DEFINE_SETTINGFACT(forceVideoDecoder)
    DEFINE_SETTINGFACT(forceCpuVideoPath)
    DEFINE_SETTINGFACT(videoConversionElement)
    DEFINE_SETTINGFACT(disablePixelAspectRatio)
    DEFINE_SETTINGFACT(frameSmoothingEnabled)

    Q_PROPERTY(bool     streamConfigured        READ streamConfigured       NOTIFY streamConfiguredChanged)
    Q_PROPERTY(QString  rtspVideoSource         READ rtspVideoSource        CONSTANT)
    Q_PROPERTY(QString  udp264VideoSource       READ udp264VideoSource      CONSTANT)
    Q_PROPERTY(QString  udp265VideoSource       READ udp265VideoSource      CONSTANT)
    Q_PROPERTY(QString  tcpVideoSource          READ tcpVideoSource         CONSTANT)
    Q_PROPERTY(QString  mpegtsVideoSource       READ mpegtsVideoSource      CONSTANT)
    Q_PROPERTY(QString  disabledVideoSource     READ disabledVideoSource    CONSTANT)

    bool     streamConfigured       ();
    QString  rtspVideoSource        () { return videoSourceRTSP; }
    QString  udp264VideoSource      () { return videoSourceUDPH264; }
    QString  udp265VideoSource      () { return videoSourceUDPH265; }
    QString  tcpVideoSource         () { return videoSourceTCP; }
    QString  mpegtsVideoSource      () { return videoSourceMPEGTS; }
    QString  disabledVideoSource    () { return videoDisabled; }

    static constexpr const char* videoSourceNoVideo           = QT_TRANSLATE_NOOP("VideoSettings", "No Video Available");
    static constexpr const char* videoDisabled                = QT_TRANSLATE_NOOP("VideoSettings", "Video Stream Disabled");
    static constexpr const char* videoSourceRTSP              = QT_TRANSLATE_NOOP("VideoSettings", "RTSP Video Stream");
    static constexpr const char* videoSourceUDPH264           = QT_TRANSLATE_NOOP("VideoSettings", "UDP h.264 Video Stream");
    static constexpr const char* videoSourceUDPH265           = QT_TRANSLATE_NOOP("VideoSettings", "UDP h.265 Video Stream");
    static constexpr const char* videoSourceTCP               = QT_TRANSLATE_NOOP("VideoSettings", "TCP-MPEG2 Video Stream");
    static constexpr const char* videoSourceMPEGTS            = QT_TRANSLATE_NOOP("VideoSettings", "MPEG-TS Video Stream");
    static constexpr const char* videoSource3DRSolo           = QT_TRANSLATE_NOOP("VideoSettings", "3DR Solo (requires restart)");
    static constexpr const char* videoSourceParrotDiscovery   = QT_TRANSLATE_NOOP("VideoSettings", "Parrot Discovery");
    static constexpr const char* videoSourceYuneecMantisG     = QT_TRANSLATE_NOOP("VideoSettings", "Yuneec Mantis G");
    static constexpr const char* videoSourceHerelinkAirUnit   = QT_TRANSLATE_NOOP("VideoSettings", "Herelink AirUnit");
    static constexpr const char* videoSourceHerelinkHotspot   = QT_TRANSLATE_NOOP("VideoSettings", "Herelink Hotspot");

signals:
    void streamConfiguredChanged    (bool configured);

private slots:
    void _configChanged             (QVariant value);
    // STRATUM: reads AppSettings.stratumProfile and copies the profile-scoped RTSP URL
    // (daggerRtspUrl for Dagger, tvRtspUrl for Dropper) into the active rtspUrl fact.
    // Idempotent + preserves TV/IR toggle state under Dropper. See implementation.
    void _applyStratumProfileToRtsp ();

private:
    void _setDefaults               ();
    void _setForceVideoDecodeList();

private:
    bool _noVideo = false;

};
