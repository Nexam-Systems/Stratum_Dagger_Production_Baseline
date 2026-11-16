#pragma once

#include <QtCore/qcontainerfwd.h>

class QQuickItem;
class QVideoSink;
class VideoReceiver;
class QString;

namespace GStreamer
{

enum VideoDecoderOptions {
    ForceVideoDecoderDefault = 0,
    ForceVideoDecoderSoftware,
    ForceVideoDecoderNVIDIA,
    ForceVideoDecoderVAAPI,
    ForceVideoDecoderDirectX3D,
    ForceVideoDecoderVideoToolbox,
    ForceVideoDecoderIntel,
    ForceVideoDecoderVulkan,
    ForceVideoDecoderHardware
};

void prepareEnvironment();
bool initialize();
bool completeInit();
void setDebugLevel(int level);
void *createVideoSink(QQuickItem *widget, QObject *parent = nullptr);
void releaseVideoSink(void *sink);
VideoReceiver *createVideoReceiver(QObject *parent = nullptr);

/// Connect the appsink inside @p sinkBin to @p videoSink. Returns true on success.
bool setupAppSinkAdapter(void *sinkBin, QVideoSink *videoSink, QObject *adapterParent);

/// Toggle every appsink adapter parented under @p adapterParent. Used to drop frames at
/// the appsink while the host window is hidden/minimized — saves CPU vs. running the
/// full decode→render path against a non-visible sink. Safe to call repeatedly; no-op
/// when no adapters exist.
void setAppSinkAdaptersActive(QObject *adapterParent, bool active);

/// STRATUM #37: stitch recorded GCS segments (temp per-feed files produced across TV/IR
/// switches) into a single continuous @p outputFile. Each segment is decoded, scaled to one
/// target resolution (TV and IR differ) and re-encoded through one muxer, so the result is a
/// single valid file. Blocking — run on a worker thread. Returns false (with @p errorOut set)
/// on failure, leaving the segments untouched so no footage is lost.
bool mergeVideoSegments(const QStringList &segmentFiles, const QString &outputFile,
                        QString *errorOut = nullptr);

}
