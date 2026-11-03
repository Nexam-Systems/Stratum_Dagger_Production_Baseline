#include "VideoSettings.h"
#include "VideoManager.h"

#include "QGCLoggingCategory.h"
#include <QtCore/QSettings>
#include <QtCore/QVariantList>

// STRATUM: for stratumProfile-driven RTSP URL auto-selection. AppSettings is
// constructed by SettingsManager BEFORE VideoSettings (see SettingsManager::init),
// so it is safe to reach through the manager from our ctor.
#include "SettingsManager.h"
#include "AppSettings.h"

QGC_LOGGING_CATEGORY(VideoSettingsLog, "Settings.VideoSettings")

#ifdef QGC_GST_STREAMING
#include "GStreamer.h"
static constexpr bool kGstEnabled = true;
#else
static constexpr bool kGstEnabled = false;
#endif
#ifndef QGC_DISABLE_UVC
#include "UVCReceiver.h"
#endif

DECLARE_SETTINGGROUP(Video, "Video")
{
    // Setup enum values for videoSource settings into meta data
    QVariantList videoSourceList;
#if defined(QGC_GST_STREAMING) || defined(QGC_QT_STREAMING)
    videoSourceList.append(videoSourceRTSP);
    videoSourceList.append(videoSourceUDPH264);
    videoSourceList.append(videoSourceUDPH265);
    videoSourceList.append(videoSourceTCP);
    videoSourceList.append(videoSourceMPEGTS);
    videoSourceList.append(videoSource3DRSolo);
    videoSourceList.append(videoSourceParrotDiscovery);
    videoSourceList.append(videoSourceYuneecMantisG);

    #ifdef QGC_HERELINK_AIRUNIT_VIDEO
        videoSourceList.append(videoSourceHerelinkAirUnit);
    #else
        videoSourceList.append(videoSourceHerelinkHotspot);
    #endif
#endif
#ifndef QGC_DISABLE_UVC
    QStringList uvcDevices = UVCReceiver::getDeviceNameList();
    for (const QString& device : uvcDevices) {
        videoSourceList.append(device);
    }
#endif
    if (videoSourceList.count() == 0) {
        _noVideo = true;
        videoSourceList.append(videoSourceNoVideo);
        setUserVisible(false);
    } else {
        videoSourceList.insert(0, videoDisabled);
    }

    // make translated strings
    QStringList videoSourceCookedList;
    for (const QVariant& videoSource: videoSourceList) {
        videoSourceCookedList.append( VideoSettings::tr(videoSource.toString().toStdString().c_str()) );
    }

    _nameToMetaDataMap[videoSourceName]->setEnumInfo(videoSourceCookedList, videoSourceList);

    _setForceVideoDecodeList();

    // Migrate legacy gpuZeroCopyEnabled (pre-rename) into the new force-CPU semantics.
    {
        QSettings settings;
        settings.beginGroup(settingsGroup);
        const bool hasLegacy = settings.contains(QStringLiteral("gpuZeroCopyEnabled"));
        const bool hasNew    = settings.contains(forceCpuVideoPathName);
        if (hasLegacy) {
            if (!hasNew) {
                const bool gpuZeroCopy = settings.value(QStringLiteral("gpuZeroCopyEnabled")).toBool();
                forceCpuVideoPath()->setRawValue(!gpuZeroCopy);
            }
            settings.remove(QStringLiteral("gpuZeroCopyEnabled"));
        }
        settings.endGroup();
    }

    // Set default value for videoSource
    _setDefaults();

    // STRATUM: profile-driven RTSP URL selection. Watch three sources of change:
    //   1. AppSettings.stratumProfile -- user picks a profile (or switches later),
    //      we must re-copy the profile-scoped URL into the active rtspUrl.
    //   2. daggerRtspUrl edits -- if we're on Dagger, propagate the edit to rtspUrl
    //      so the change is applied without a restart.
    //   3. tvRtspUrl edits -- ditto for Dropper's default (TV) feed. irRtspUrl edits
    //      are only visible after the user re-selects the IR button in
    //      FlyViewCameraControls, matching the existing TV/IR toggle contract.
    //
    // Skip if AppSettings is somehow not yet up (defensive; ordering above should
    // guarantee it).
    if (auto *app = SettingsManager::instance()->appSettings()) {
        connect(app->stratumProfile(),  &Fact::rawValueChanged, this, &VideoSettings::_applyStratumProfileToRtsp);
        connect(daggerRtspUrl(),        &Fact::rawValueChanged, this, &VideoSettings::_applyStratumProfileToRtsp);
        connect(daggerC12TvRtspUrl(),   &Fact::rawValueChanged, this, &VideoSettings::_applyStratumProfileToRtsp);
        connect(daggerC12IrRtspUrl(),   &Fact::rawValueChanged, this, &VideoSettings::_applyStratumProfileToRtsp);
        connect(daggerCamera(),         &Fact::rawValueChanged, this, &VideoSettings::_applyStratumProfileToRtsp);
        connect(tvRtspUrl(),            &Fact::rawValueChanged, this, &VideoSettings::_applyStratumProfileToRtsp);

        // Seed on startup. Queued so we run AFTER settings finish loading and the
        // event loop is up (avoids any surprise reentry during the ctor).
        QMetaObject::invokeMethod(this, &VideoSettings::_applyStratumProfileToRtsp, Qt::QueuedConnection);
    }
}

void VideoSettings::_setDefaults()
{
    if (_noVideo) {
        _nameToMetaDataMap[videoSourceName]->setRawDefaultValue(videoSourceNoVideo);
    } else {
        _nameToMetaDataMap[videoSourceName]->setRawDefaultValue(videoDisabled);
    }
}

DECLARE_SETTINGSFACT(VideoSettings, aspectRatio)
DECLARE_SETTINGSFACT(VideoSettings, videoFit)
DECLARE_SETTINGSFACT(VideoSettings, gridLines)
DECLARE_SETTINGSFACT(VideoSettings, showRecControl)
DECLARE_SETTINGSFACT(VideoSettings, recordingFormat)
DECLARE_SETTINGSFACT(VideoSettings, maxVideoSize)
DECLARE_SETTINGSFACT(VideoSettings, enableStorageLimit)
DECLARE_SETTINGSFACT(VideoSettings, streamEnabled)
DECLARE_SETTINGSFACT(VideoSettings, disableWhenDisarmed)

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, videoSource)
{
    if (!_videoSourceFact) {
        _videoSourceFact = _createSettingsFact(videoSourceName);
        //-- Check for sources no longer available
        if(!_videoSourceFact->enumValues().contains(_videoSourceFact->rawValue().toString())) {
            if (_noVideo) {
                _videoSourceFact->setRawValue(videoSourceNoVideo);
            } else {
                _videoSourceFact->setRawValue(videoDisabled);
            }
        }
        connect(_videoSourceFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _videoSourceFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, forceVideoDecoder)
{
    if (!_forceVideoDecoderFact) {
        _forceVideoDecoderFact = _createSettingsFact(forceVideoDecoderName);

        _forceVideoDecoderFact->setUserVisible(kGstEnabled);

        connect(_forceVideoDecoderFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _forceVideoDecoderFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, lowLatencyMode)
{
    if (!_lowLatencyModeFact) {
        _lowLatencyModeFact = _createSettingsFact(lowLatencyModeName);

        _lowLatencyModeFact->setUserVisible(kGstEnabled);

        connect(_lowLatencyModeFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _lowLatencyModeFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, forceCpuVideoPath)
{
    if (!_forceCpuVideoPathFact) {
        _forceCpuVideoPathFact = _createSettingsFact(forceCpuVideoPathName);

#if defined(QGC_HAS_ANY_GPU_PATH)
        _forceCpuVideoPathFact->setUserVisible(kGstEnabled);
#else
        _forceCpuVideoPathFact->setUserVisible(false);
#endif
    }
    return _forceCpuVideoPathFact;
}

// videoConversionElement / disablePixelAspectRatio are read by GStreamer::createVideoSink()
// at bin construction and passed as construct-only properties — no env-var indirection.
DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, videoConversionElement)
{
    if (!_videoConversionElementFact) {
        _videoConversionElementFact = _createSettingsFact(videoConversionElementName);
        _videoConversionElementFact->setUserVisible(kGstEnabled);
    }
    return _videoConversionElementFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, disablePixelAspectRatio)
{
    if (!_disablePixelAspectRatioFact) {
        _disablePixelAspectRatioFact = _createSettingsFact(disablePixelAspectRatioName);
        _disablePixelAspectRatioFact->setUserVisible(kGstEnabled);
    }
    return _disablePixelAspectRatioFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, frameSmoothingEnabled)
{
    if (!_frameSmoothingEnabledFact) {
        _frameSmoothingEnabledFact = _createSettingsFact(frameSmoothingEnabledName);
        _frameSmoothingEnabledFact->setUserVisible(kGstEnabled);
    }
    return _frameSmoothingEnabledFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, rtspTimeout)
{
    if (!_rtspTimeoutFact) {
        _rtspTimeoutFact = _createSettingsFact(rtspTimeoutName);

        _rtspTimeoutFact->setUserVisible(kGstEnabled);

        connect(_rtspTimeoutFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _rtspTimeoutFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, udpUrl)
{
    if (!_udpUrlFact) {
        _udpUrlFact = _createSettingsFact(udpUrlName);
        connect(_udpUrlFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _udpUrlFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, rtspUrl)
{
    if (!_rtspUrlFact) {
        _rtspUrlFact = _createSettingsFact(rtspUrlName);
        connect(_rtspUrlFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _rtspUrlFact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, tcpUrl)
{
    if (!_tcpUrlFact) {
        _tcpUrlFact = _createSettingsFact(tcpUrlName);
        connect(_tcpUrlFact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _tcpUrlFact;
}

// STRATUM: stored TV / IR feed URLs. These do not drive the pipeline directly — the
// TV/IR camera buttons copy the chosen one into rtspUrl (which restarts the stream),
// so no _configChanged connection is needed here.
DECLARE_SETTINGSFACT(VideoSettings, tvRtspUrl)
DECLARE_SETTINGSFACT(VideoSettings, irRtspUrl)
// STRATUM: stored Dagger camera feeds. Contract matches tvRtspUrl/irRtspUrl -- the
// URL is stored but the active pipeline is rtspUrl. _applyStratumProfileToRtsp copies
// the right one into rtspUrl based on the Dagger profile + daggerCamera selection.
DECLARE_SETTINGSFACT(VideoSettings, daggerRtspUrl)        // A2 mini feed
DECLARE_SETTINGSFACT(VideoSettings, daggerC12TvRtspUrl)   // C12 TV feed
DECLARE_SETTINGSFACT(VideoSettings, daggerC12IrRtspUrl)   // C12 IR feed
// STRATUM: 0 = A2 mini, 1 = C12. Selecting a camera swaps the active RTSP URL to the
// matching stored feed and the Dagger camera-control panel changes its control cluster.
DECLARE_SETTINGSFACT(VideoSettings, daggerCamera)
// STRATUM: SIYI A2 mini SDK network target for the Dagger camera-control panel.
// Read by VideoManager::sendSiyiCameraAction each command; edits take effect immediately.
DECLARE_SETTINGSFACT(VideoSettings, daggerCameraSdkHost)
DECLARE_SETTINGSFACT(VideoSettings, daggerCameraSdkPort)
// STRATUM: Current C12 gimbal IP. Read by every C12 command in VideoManager and
// rewritten by setC12CameraIp() after a successful reprogram.
DECLARE_SETTINGSFACT(VideoSettings, daggerC12Host)
// STRATUM: DIP V2 AES-128 key (32 hex chars). When set, VideoManager decodes the
// connected vehicle's 8-byte device frame (AUTOPILOT_VERSION uid) and auto-provisions
// the C12 camera IP + TV/IR RTSP URLs. Empty disables auto-provisioning.
DECLARE_SETTINGSFACT(VideoSettings, daggerDeviceKey)

bool VideoSettings::streamConfigured(void)
{
    //-- First, check if it's autoconfigured
    if(VideoManager::instance()->autoStreamConfigured()) {
        qCDebug(VideoSettingsLog) << "Stream auto configured";
        return true;
    }
    //-- Check if it's disabled
    QString vSource = videoSource()->rawValue().toString();
    if(vSource == videoSourceNoVideo || vSource == videoDisabled) {
        return false;
    }
    //-- If UDP, check for URL
    if(vSource == videoSourceUDPH264 || vSource == videoSourceUDPH265) {
        qCDebug(VideoSettingsLog) << "Testing configuration for UDP Stream:" << udpUrl()->rawValue().toString();
        return !udpUrl()->rawValue().toString().isEmpty();
    }
    //-- If RTSP, check for URL
    if(vSource == videoSourceRTSP) {
        qCDebug(VideoSettingsLog) << "Testing configuration for RTSP Stream:" << rtspUrl()->rawValue().toString();
        return !rtspUrl()->rawValue().toString().isEmpty();
    }
    //-- If TCP, check for URL
    if(vSource == videoSourceTCP) {
        qCDebug(VideoSettingsLog) << "Testing configuration for TCP Stream:" << tcpUrl()->rawValue().toString();
        return !tcpUrl()->rawValue().toString().isEmpty();
    }
    //-- If MPEG-TS, check for URL
    if(vSource == videoSourceMPEGTS) {
        qCDebug(VideoSettingsLog) << "Testing configuration for MPEG-TS Stream:" << udpUrl()->rawValue().toString();
        return !udpUrl()->rawValue().toString().isEmpty();
    }
    //-- If Herelink Air unit, good to go
    if(vSource == videoSourceHerelinkAirUnit) {
        qCDebug(VideoSettingsLog) << "Stream configured for Herelink Air Unit";
        return true;
    }
    //-- If Herelink Hotspot, good to go
    if(vSource == videoSourceHerelinkHotspot) {
        qCDebug(VideoSettingsLog) << "Stream configured for Herelink Hotspot";
        return true;
    }
#ifndef QGC_DISABLE_UVC
    if (UVCReceiver::enabled() && UVCReceiver::deviceExists(vSource)) {
        qCDebug(VideoSettingsLog) << "Stream configured for UVC";
        return true;
    }
#endif
    return false;
}

void VideoSettings::_configChanged(QVariant)
{
    emit streamConfiguredChanged(streamConfigured());
}

// STRATUM: profile-driven RTSP URL selection.
//
// Reads AppSettings.stratumProfile and, if the currently active rtspUrl does not match
// the URL(s) belonging to that profile, overwrites rtspUrl with the profile's default
// feed. That way the operator only has to type all three URLs once in Application
// Settings > Video and the UI picks the right one at runtime.
//
//   Dagger  (profile == 2):  rtspUrl depends on daggerCamera:
//                              0 (A2 mini) -> daggerRtspUrl
//                              1 (C12)     -> daggerC12TvRtspUrl (default TV);
//                                             preserve TV/IR toggle if already on IR.
//   Dropper (profile == 1):  rtspUrl <- tvRtspUrl (default). The TV/IR toggle in
//                            FlyViewCameraControls may then swap it to irRtspUrl;
//                            we preserve that toggle state by NOT overwriting rtspUrl
//                            when it already matches either of the Dropper URLs.
//   Not selected (0):        do nothing -- the profile-selection dialog will fire
//                            this again after the user picks a profile.
//
// Empty stored URLs are ignored (the operator hasn't entered one yet). We also leave
// videoSource alone; if the operator is on UDP/TCP that's a deliberate choice.
void VideoSettings::_applyStratumProfileToRtsp()
{
    auto *app = SettingsManager::instance()->appSettings();
    if (!app) {
        return;
    }

    const uint32_t profile     = app->stratumProfile()->rawValue().toUInt();
    const QString  active      = rtspUrl()->rawValue().toString();
    const QString  a2Feed      = daggerRtspUrl()->rawValue().toString();
    const QString  c12Tv       = daggerC12TvRtspUrl()->rawValue().toString();
    const QString  c12Ir       = daggerC12IrRtspUrl()->rawValue().toString();
    const QString  tv          = tvRtspUrl()->rawValue().toString();
    const QString  ir          = irRtspUrl()->rawValue().toString();
    const uint32_t daggerCam   = daggerCamera()->rawValue().toUInt();

    QString target;
    if (profile == 2) {                                     // Dagger
        if (daggerCam == 1) {                               // C12 selected
            // Keep active if it's already one of the two C12 feeds (preserves TV/IR).
            if (!c12Tv.isEmpty() && active == c12Tv) return;
            if (!c12Ir.isEmpty() && active == c12Ir) return;
            target = c12Tv;
        } else {                                            // A2 mini selected
            target = a2Feed;
        }
    } else if (profile == 1) {                              // Dropper
        // If the pipeline is already pinned to one of the two Dropper feeds, keep it
        // (preserves TV/IR toggle state). Otherwise default to TV.
        if (!tv.isEmpty() && active == tv) return;
        if (!ir.isEmpty() && active == ir) return;
        target = tv;
    } else {
        // Profile not selected yet -- wait for the dialog.
        return;
    }

    if (target.isEmpty() || target == active) {
        return;
    }

    qCDebug(VideoSettingsLog) << "STRATUM: rtspUrl <-" << target
                              << "(profile" << profile << ", daggerCamera" << daggerCam << ")";
    rtspUrl()->setRawValue(target);
}

void VideoSettings::_setForceVideoDecodeList()
{
#ifdef QGC_GST_STREAMING
    static const QList<GStreamer::VideoDecoderOptions> removeForceVideoDecodeList{
#if defined(Q_OS_ANDROID)
    GStreamer::VideoDecoderOptions::ForceVideoDecoderDirectX3D,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVideoToolbox,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVAAPI,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderNVIDIA,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderIntel,
#elif defined(Q_OS_LINUX)
    GStreamer::VideoDecoderOptions::ForceVideoDecoderDirectX3D,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVideoToolbox,
#elif defined(Q_OS_WIN)
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVideoToolbox,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVulkan,
#elif defined(Q_OS_MACOS)
    GStreamer::VideoDecoderOptions::ForceVideoDecoderDirectX3D,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVAAPI,
#elif defined(Q_OS_IOS)
    GStreamer::VideoDecoderOptions::ForceVideoDecoderDirectX3D,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderVAAPI,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderNVIDIA,
    GStreamer::VideoDecoderOptions::ForceVideoDecoderIntel,
#endif
    };

    for (const auto &value : removeForceVideoDecodeList) {
        _nameToMetaDataMap[forceVideoDecoderName]->removeEnumInfo(value);
    }
#endif
}
