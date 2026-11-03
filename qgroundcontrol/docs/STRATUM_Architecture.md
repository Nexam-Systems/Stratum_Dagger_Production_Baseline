# STRATUM Ground Station — Backend Architecture

> Developer reference. Explains what STRATUM is, how the pieces fit together, and how
> it talks to PX4, the companion computer, the pod, and the SIYI camera. Intended
> reading for anyone adding a feature, wiring a new message, or debugging a live link.

---

## 1. What is STRATUM?

STRATUM Desktop is a **fork of QGroundControl (Qt 6, QML front-end, C++ back-end)**
carrying our own mission-specific glue on top of stock PX4 telemetry. It is not a
plugin — the C++ tree in [src/](../src) is patched directly, and a small
STRATUM-owned MAVLink dialect
([src/MAVLink/mavlink_definitions/stratum.xml](../src/MAVLink/mavlink_definitions/stratum.xml))
is appended to the upstream aggregate at build time.

Two operator profiles run on the same binary:

| Profile      | Enum value | Airframe use-case                                 | Vehicle-side stack                                    |
|--------------|------------|---------------------------------------------------|-------------------------------------------------------|
| **Dropper**  | `1`        | Payload dropper.                                  | PX4 + a **bridge companion computer** (comp-id `191`) that owns the standoff execution logic. |
| **Dagger**   | `2`        | Strike / targeting airframe.                      | Patched PX4 that carries native `Standoff`, `Engagement`, `Vision Engagement`, `PN Engagement`, `Abort` custom modes.  |

The profile is a single fact — `appSettings.stratumProfile` (see
[App.SettingsGroup.json](../src/Settings/App.SettingsGroup.json)) — and every
Dropper-vs-Dagger branch in the tree keys off it. As of the current STRATUM UX
spec, the profile picker is hidden and Dagger is forced at startup
(see [MainWindow.qml](../src/MainWindow/MainWindow.qml)); the profile machinery
is retained so the Dropper path can be re-enabled by flipping the default.

---

## 2. Repository layout (STRATUM additions live inside QGC's tree)

```
qgroundcontrol/
├── src/
│   ├── FirmwarePlugin/PX4/PX4FirmwarePlugin.cc  # Custom flight modes + engagement stream request
│   ├── FlyView/                                 # Fly view UI + Dagger-specific controllers
│   │   ├── StandoffController.qml               # Standoff commit (Dagger + Dropper paths)
│   │   ├── EngagementController.qml             # Engage / Vision / PN / Abort safety loop
│   │   ├── FlyViewToolStripActionList.qml       # Right-hand action strip (visibility gates)
│   │   ├── FlyViewMap.qml                       # AOP polygon edit / range check
│   │   ├── FlyViewWidgetLayer.qml               # Standoff panel + AOP edit bar
│   │   ├── FlyViewCameraControlsDaggerRoot.qml  # C12 PRO camera-control host
│   │   └── TrackerRoiOverlay.qml                # Companion tracker ROI overlay
│   ├── TargetFetch/TargetFetchManager.*         # XC25 pod ping + passive target read
│   ├── VideoManager/VideoManager.cc             # SIYI A2 mini SDK v3 UDP sender
│   ├── Vehicle/Vehicle.{h,cc}                   # setTrackerEnabled / setTrackerRoi / guidedModeStandoff
│   ├── MissionManager/GeoFenceController.*      # AOP polygon → PX4 inclusion fence upload
│   ├── MAVLink/mavlink_definitions/stratum.xml  # Custom dialect (42001…42006)
│   ├── Settings/
│   │   ├── App.SettingsGroup.json               # stratumProfile fact
│   │   ├── FlyView.SettingsGroup.json           # maxGoToLocationDistance, maxAOPDistance
│   │   ├── VideoSettings.cc                     # Profile-driven RTSP swap
│   │   └── FlyViewSettings.{h,cc}               # DECLARE/DEFINE for each fact
│   ├── AppSettings/pages/*.SettingsUI.json      # Sidebar page JSON (generated → QML at build)
│   └── AppSettings/HelpSettings.qml             # Customer-facing help
├── tools/generators/settings_qml/               # Python generator: JSON → SettingsPagesModel.qml
└── docs/STRATUM_Architecture.md                 # THIS FILE
```

---

## 3. Runtime architecture

```
                            ┌──────────────────────────────┐
                            │   Qt/QML front-end (Fly View,│
                            │   settings, dialogs, panels) │
                            └──────────────┬───────────────┘
                                           │ Fact system (Q_PROPERTY / Fact*)
                                           ▼
                            ┌──────────────────────────────┐
                            │   STRATUM QML controllers    │
                            │  StandoffController          │
                            │  EngagementController        │
                            │  FlyViewMap (AOP)            │
                            └──┬────────────────────┬──────┘
       Q_INVOKABLE / signals   │                    │  Q_INVOKABLE
                               ▼                    ▼
    ┌──────────────────────────────┐   ┌──────────────────────────────┐
    │ Vehicle (C++)                │   │ TargetFetchManager (C++)     │
    │  - MAVLink send/receive      │   │  - Pod UDP ping / status     │
    │  - guidedModeStandoff        │   │  - Publishes QGeoCoordinate  │
    │  - setTrackerEnabled/Roi     │   │    to QML                    │
    │  - sendCommand (int/long)    │   └──────────┬───────────────────┘
    │  - homePosition / coordinate │              │  raw UDP (side-channel,
    └──┬──────────────┬────────────┘              │  not through MAVLink)
       │              │                           ▼
       │              │              ┌──────────────────────────────┐
       │              │              │ XC25 Pod (192.168.1.253)     │
       │              │              └──────────────────────────────┘
       │              │
       │              ▼
       │  ┌──────────────────────────────┐         ┌──────────────────────────────┐
       │  │ PX4FirmwarePlugin (C++)      │         │ VideoManager (C++)           │
       │  │  - flightModes registration  │         │  - RTSP feed switching        │
       │  │  - Standoff / Engagement /   │         │  - SIYI A2 mini SDK v3 UDP    │
       │  │    Vision / PN nav_state map │         │    packet build + send        │
       │  └──────────────────────────────┘         └──────────────┬────────────────┘
       │                                                          │  UDP (SIYI)
       │  MAVLink                                                 ▼
       ▼                                             ┌────────────────────────────┐
┌──────────────────────────────────────────────┐     │ SIYI A2 mini gimbal        │
│ MAVLink transport (UDP / serial / TCP)       │     │ (192.168.144.25:37260)     │
└──────────────────────┬───────────────────────┘     └────────────────────────────┘
                       │ id `1` (autopilot) / id `191` (bridge)
                       ▼
     ┌──────────────────────────────────────────────────────────┐
     │  PX4 (Dagger patched or stock) + Companion computer      │
     │   - AUTO_STANDOFF / AUTO_ENGAGEMENT / AUTO_VISION / PN   │
     │   - Bridge (comp-id 191) executes Dropper standoff via   │
     │     MAV_CMD 31010 / 31011                                │
     │   - Companion tracker consumes NEXAM_TRACKER_CONFIG      │
     │     (42005), emits NEXAM_TARGET_TRACK (42004)            │
     │   - Engagement telemetry: 42001 / 42002 / 42006 @ ~5 Hz  │
     └──────────────────────────────────────────────────────────┘
```

**Two key rules:**

1. Every operator command that touches the aircraft either goes through `Vehicle`
   (MAVLink) or through a **dedicated side-channel manager** (`TargetFetchManager`
   for the pod, `VideoManager::sendSiyiCameraAction` for SIYI). QML never opens
   raw sockets.
2. The **profile fact** (`stratumProfile`) fans out to every branch that would
   otherwise be a runtime type check. Files that read it use a QML computed
   property `_stratumIsDagger` / `_stratumIsDropper` — never inline the enum
   value.

---

## 4. Communication channels

STRATUM speaks over **five** distinct channels. Only one of them is MAVLink to the
autopilot; each has its own trust boundary and lifecycle.

### 4.1 MAVLink to PX4 (main link)

- **Transport:** whatever the operator chose (UDP / serial / TCP), managed by
  QGC's `LinkManager` and multiplexed in `MAVLinkProtocol`.
- **Dialect:** `stratum` — QGC-side compile-time selection via `QGC_MAVLINK_DIALECT`
  in `cmake/CustomOptions.cmake`. The dialect XML includes upstream `all.xml`
  and appends 42001–42006 (see [STRATUM MAVLink dialect](#5-stratum-mavlink-dialect)).
- **System / component ids:**
  - `sysid` — the vehicle (default 1). Set on connect via `Vehicle::id()`.
  - `compid = 1` (autopilot) — target for flight-mode set, standoff command.
  - `compid = 191` (bridge / companion) — target for Dropper standoff commit and
    for the tracker `setTrackerEnabled/setTrackerRoi` traffic.
- **Custom commands used**: see [Custom commands (COMMAND_INT / COMMAND_LONG)](#52-custom-commands-command_int--command_long).
- **Streamed messages consumed**: `ENGAGEMENT_STATUS` (42001, ~5 Hz),
  `VISION_ENGAGEMENT_STATUS` (42002), `PN_ENGAGEMENT_STATUS` (42006),
  `NEXAM_TARGET_TRACK` (42004).

The engagement stream is explicitly requested at connect time by
[PX4FirmwarePlugin::initializeVehicle](../src/FirmwarePlugin/PX4/PX4FirmwarePlugin.cc#L182-L196)
so the abort countdown always has live data even on firmwares that don't stream
it by default.

### 4.2 MAVLink to the companion computer (Dropper only)

Same link, different `compid`. Used for:

- Dropper standoff commit — `MAV_CMD 31010` (params) + `31011` (activate),
  addressed to `compid = 191`. See
  [StandoffController.qml](../src/FlyView/StandoffController.qml).
- Companion tracker on Dagger — `NEXAM_TRACKER_CONFIG` (42005),
  `NEXAM_TARGET_SELECT` (42003) egress; `NEXAM_TARGET_TRACK` (42004) ingress.

### 4.3 XC25 pod — direct UDP (side-channel)

- **Transport:** raw UDP, sockets owned by
  [TargetFetchManager](../src/TargetFetch/TargetFetchManager.h).
- **Wire:** SIYI-family 0x55/0xAA/0xDC frame family; the pod is a single-client
  streamer so the manager sends a brief "M" heartbeat burst (25 Hz × ~5 s) to
  register itself, then goes passive and listens for status frames on port
  `4000`. Command port is `1030`; pod IP is `192.168.1.253` by default.
- **Product:** decoded `T1` target → `QGeoCoordinate`, exposed as
  `QGroundControl.targetFetch.targetCoordinate` to QML, plotted on the map.
- **Runs entirely without a MAVLink link.** This is deliberate — the pod may be
  registered before the main autopilot is even powered up.

Note: the tool-strip buttons that drive this manager (`Connect Pod`,
`Fetch Target`) are currently hidden per the STRATUM UX spec but the manager
itself is unchanged and can be triggered by flipping `visible: false` back to
`_root._stratumIsDagger` in
[FlyViewToolStripActionList.qml](../src/FlyView/FlyViewToolStripActionList.qml).

### 4.4 SIYI A2 mini — direct UDP (side-channel)

- **Transport:** UDP, socket owned by
  [VideoManager](../src/VideoManager/VideoManager.cc).
- **Wire:** SIYI SDK v3. Frame layout is documented in the comment block above
  `_siyiPacket` — STX `0x55 0x66`, `CTRL = 0x01` (need-ACK), monotonic per-process
  sequence, CRC-16/XMODEM tail.
- **Commands used**: Center (`0x08`), Rate (`0x07`), Photo/Record/Mode
  (`0x0C`, func_type 0..5).
- **Destination**: `videoSettings.daggerCameraSdkHost` /
  `daggerCameraSdkPort` (defaults `192.168.144.25:37260`), editable at runtime.
- **QML entry point**: `QGroundControl.videoManager.sendCameraAction(name)`
  from [FlyViewCameraControls.qml](../src/FlyView/FlyViewCameraControls.qml) (C12 PRO).

### 4.5 RTSP video

- Standard GStreamer pipeline built by upstream QGC's `VideoManager`.
- The active RTSP URL is auto-swapped by
  [`VideoSettings::_applyStratumProfileToRtsp`](../src/Settings/VideoSettings.cc#L351)
  based on `stratumProfile` × `daggerCamera` (A2 mini = 0, C12 = 1).

---

## 5. STRATUM MAVLink dialect

All STRATUM messages live in
[stratum.xml](../src/MAVLink/mavlink_definitions/stratum.xml). CRC parity with the
PX4 firmware is critical — do **not** reorder or rename fields.

### 5.1 Custom messages (42001–42006)

| ID    | Name                        | Direction   | Purpose                                                                 |
|-------|-----------------------------|-------------|-------------------------------------------------------------------------|
| 42001 | `ENGAGEMENT_STATUS`         | PX4 → GCS   | Coordinate-Engagement TTI, range, closing speed. Drives abort countdown. |
| 42002 | `VISION_ENGAGEMENT_STATUS`  | PX4 → GCS   | Vision-Engagement LOS error, track quality, TTI. Drives vision overlay. |
| 42003 | `NEXAM_TARGET_SELECT`       | GCS → comp  | Operator draw / click on video → tracker seed box.                     |
| 42004 | `NEXAM_TARGET_TRACK`        | comp → GCS  | Per-frame tracked-box state → live green box on the video overlay.     |
| 42005 | `NEXAM_TRACKER_CONFIG`      | GCS → comp  | Tracker on/off + centered ROI diagonal fraction.                        |
| 42006 | `PN_ENGAGEMENT_STATUS`      | PX4 → GCS   | PN-ENG entry-gate verdict, LOS solution, actuator authority margin.    |

Header-side entry points:

- **42005** — [`Vehicle::setTrackerEnabled(bool)`](../src/Vehicle/Vehicle.h#L410-L413)
  and `setTrackerRoi(...)`: each mutates one field of the cached tracker config and
  re-emits the full 42005 frame. This means enable + ROI always travel together and
  the companion can be dropped/re-connected without partial state.
- **42003** — QML overlay drag / click handlers in `FlyViewVideo.qml` /
  `TrackerRoiOverlay.qml`.

### 5.2 Custom commands (COMMAND_INT / COMMAND_LONG)

| ID     | Name (STRATUM)          | Target       | Sent from                                                                     |
|--------|-------------------------|--------------|-------------------------------------------------------------------------------|
| 31010  | `DO_STANDOFF`           | Dagger: PX4 (compid 1) / Dropper: bridge (compid 191) | [`PX4FirmwarePlugin::guidedModeStandoff`](../src/FirmwarePlugin/PX4/PX4FirmwarePlugin.cc#L430-L462) (Dagger) / [`StandoffController.beginStandoff`](../src/FlyView/StandoffController.qml) (Dropper) |
| 31011  | `STANDOFF_ACTIVATE`     | Bridge (191) | Dropper-only. Sent by `StandoffController.beginStandoff` immediately after 31010. Activate=`1` starts, `0` cancels. |

Everything else is stock MAVLink (`MAV_CMD_DO_SET_MODE`, `MAV_CMD_DO_REPOSITION`,
`MAV_CMD_SET_MESSAGE_INTERVAL`, etc.).

### 5.3 Standoff wire contract (Dagger — MAV_CMD 31010)

Documented inline in the firmware plugin. Frame **must** be
`MAV_FRAME_GLOBAL_RELATIVE_ALT`; local frames corrupt the lat/lon scaling.

| Field | Semantic |
|-------|----------|
| `x`  | Target latitude (`COMMAND_INT` scales the double to 1e7 int) |
| `y`  | Target longitude |
| `z`  | Standoff height above home [m] (PX4 adds home altitude) |
| `p1` | Distance from target [m] |
| `p2` | Direction: compass bearing target → hold point [deg, 0=N, CW] |
| `p3` | Reserved (`0.0`) |
| `p4` | Yaw — send `NaN` so PX4 faces the target itself |

---

## 6. Custom PX4 flight modes

Defined at the top of
[`PX4FirmwarePlugin::PX4FirmwarePlugin()`](../src/FirmwarePlugin/PX4/PX4FirmwarePlugin.cc#L25-L100).

| Display name (`qsTr`) | PX4 `custom_mode` enum         | Custom sub-mode | Notes                                                              |
|-----------------------|--------------------------------|-----------------|--------------------------------------------------------------------|
| `Standoff`            | `AUTO_STANDOFF`                | 20              | Target-relative orbit. Commanded by MAV_CMD 31010 + mode-set.       |
| `Engagement`          | `AUTO_ENGAGEMENT`              | 21              | Terminal run against latched standoff target.                       |
| `Vision Engagement`   | `AUTO_VISION_ENGAGEMENT`       | 23              | Camera-guided terminal run; no map target.                          |
| `PN Engagement`       | `AUTO_PN_ENGAGEMENT` (`nav_state 30`) | 24        | Proportional-navigation + closing-speed regulator.                  |
| `Abort`               | `AUTO_ABORT`                   | 22              | Break-off to a pushed `ABRT_*` destination.                         |
| `Safe Recovery`       | (stock `AUTO_RTL`; label override) | —          | Whitelisted by the operator UX as `Safe Recovery`.                  |

**Whitelist:** the operator picker in
[FlightModeIndicator.qml](../src/Toolbar/FlightModeIndicator.qml) /
[FlightModeMenu.qml](../src/QmlControls/FlightModeMenu.qml) shows a subset:
`Takeoff, Land, Safe Recovery, Return, Position, Standoff, Engagement, Hold,
Abort`. PX4 `Position` is shown as `Manual` via a display-label mapping — the
firmware mode string sent to the vehicle is still `Position`.

**Reversal:** empty the `_stratumAllowedFlightModes` array to restore the full
mode list.

---

## 7. Module walkthrough

### 7.1 `Vehicle` — the MAVLink gateway

- Owns the socket, sysid/compid, and every `sendMavCommand*` variant.
- STRATUM adds:
  - `Q_INVOKABLE bool guidedModeStandoff(coord, dist, bearing, height)` — the
    only entry point through which a Standoff commit actually reaches PX4. It
    range-checks the hold point against
    `flyViewSettings.maxGoToLocationDistance` and shows a rejection toast; the
    caller (QML) treats a `false` return as a hard failure.
  - `Q_INVOKABLE void setTrackerEnabled(bool)` and `setTrackerRoi(...)` — pack
    the cached tracker config into 42005 and broadcast it.
  - Home / current coordinate expose as `homePosition` / `coordinate`.

### 7.2 `StandoffController.qml`

Single controller for both profiles. Contract:

1. Validates target + vehicle.
2. **Dagger** — calls `Vehicle.guidedModeStandoff(...)`. On `false` return, does
   **nothing**: no flight-mode switch, no `_standoffActive`, no on-map circle.
3. **Dropper** — sends `31010` (params) then `31011` (activate=1) to
   `compid = 191`.
4. On success, latches the state that drives the on-map surveillance circle
   (radius = `_standoffDistance`, centre = target).
5. `cancelStandoff()` mirrors: on Dropper it fires `31011 activate=0`; on Dagger
   the flight-mode switch alone is enough.

The Set Standoff panel in
[FlyViewWidgetLayer.qml](../src/FlyView/FlyViewWidgetLayer.qml) is the only
caller; it **only** closes the panel if `beginStandoff` returns `true` so the
operator can adjust distance/target after a range rejection.

### 7.3 `EngagementController.qml`

Central safety loop for the four engagement modes (Engage, Vision Engage,
PN Engage, Abort). Contract:

- Reads / writes `ABRT_DEST`, `ABRT_LAT`, `ABRT_LON`, `ABRT_ALT` via
  `ParameterManager`. `armAbort()` is idempotent.
- **Arm-on-engage:** every `engage()` / `visionEngage()` / `pnEngage()` calls
  `_ensureArmed()` first, guaranteeing an abort destination has been pushed to
  the vehicle *before* the mode switch.
- Session state (`abortArmed`, `_armedVehicle`) resets when the active vehicle
  changes — a freshly connected airframe is never assumed armed from a previous
  session.
- The UI gates (`engaged`, `visionEngaged`, `pnEngaged`) key off the reported
  flight mode; the corresponding overlay reads the matching `4200x` telemetry
  stream (see [Custom messages (42001–42006)](#51-custom-messages-4200142006)).

### 7.4 AOP (Area of Operations)

- Reuses the standard PX4 **inclusion polygon geofence** —
  `GeoFenceController::sendToVehicle()` uploads it as a normal fence.
- Edit lifecycle in [FlyViewMap.qml](../src/FlyView/FlyViewMap.qml):
  1. `startAOPEdit()` seeds a 1.5 km × 1.5 km box centred on the map (capped at
     3 km × 3 km by `GeoFenceController::addInclusionPolygon`).
  2. Operator drags vertices; polygons become `interactive`.
  3. `applyAOPEdit()` runs `_aopVerticesWithinRange()` — every inclusion-polygon
     vertex must sit within `flyViewSettings.maxAOPDistance` of the anchor
     (vehicle home → vehicle position → map centre fallback). On failure it
     latches `_aopRangeReject = true` and does not commit or leave edit mode.
     On success it locks the polygon and uploads.
- Standoff target rejection: `FlyViewMap.isCoordinateInsideAOP(coord)` returns
  `true` when no fence exists, otherwise requires the target inside some
  inclusion polygon. Called before every `beginStandoff` in the panel.

### 7.5 `TargetFetchManager` — pod integration

See [XC25 pod — direct UDP (side-channel)](#43-xc25-pod--direct-udp-side-channel). Application-static singleton, exposed to QML as
`QGroundControl.targetFetch`. The 30 s fetch session re-reads the pod status
every 2 s, replacing the plotted marker each pass. `pingPod()` sends a brief
25 Hz heartbeat burst (~5 s) and stops — never holds control of the pod.

### 7.6 Companion tracker

- **Config out** — `NEXAM_TRACKER_CONFIG` (42005) via
  [`Vehicle::setTrackerEnabled`](../src/Vehicle/Vehicle.cc#L3056) /
  `setTrackerRoi`. `enable` + `roi_center_{x,y}` + `roi_size` always travel
  together because each setter re-packs the full frame.
- **Selection out** — `NEXAM_TARGET_SELECT` (42003) from the operator's
  click/drag on the video overlay in
  [FlyViewVideo.qml](../src/FlyView/FlyViewVideo.qml).
- **Track in** — `NEXAM_TARGET_TRACK` (42004), one message per processed frame,
  drives the green tracked-box overlay.

### 7.7 `VideoManager` — SIYI A2 mini

- Owns the RTSP pipeline (upstream QGC).
- STRATUM adds `sendSiyiCameraAction(name)` — builds a SIYI SDK v3 packet and
  sends it over UDP to `daggerCameraSdkHost:daggerCameraSdkPort`.
- Startup init: the Dagger camera panel calls Lock + Center at load to leave the
  gimbal in a known state.
- Legal action names: `center`, `rate:<yaw>,<pitch>`, `lock`, `follow`, `fpv`,
  `photo`, `record`.

### 7.8 Settings pipeline

Settings are defined in JSON and generated into QML at build time.

- **Facts** — `src/Settings/*.SettingsGroup.json`. Each entry becomes a `Fact*`
  reachable as `QGroundControl.settingsManager.<group>.<fact>`. Every fact is
  hand-linked by `DECLARE_SETTINGSFACT` (`.cc`) + `DEFINE_SETTINGFACT` (`.h`).
- **Sidebar pages** — `src/AppSettings/pages/*.SettingsUI.json`. Compiled by
  [`tools/generators/settings_qml`](../tools/generators/settings_qml/) into
  `SettingsPagesModel.qml`, `FlyViewSettings.qml`, etc.
  - `"visible": "false"` or `"showWhen": "false"` on a page or group hides it
    without touching the rest of the tree — this is how the STRATUM UX cull
    (Analyze/Configure/Comm Links/Guided Commands/Battery Safety/MAVLink Actions,
    profile picker) is currently reversible.
  - Section-level visibility is a QML expression evaluated at runtime.
- **STRATUM-visible settings** currently live under
  **General → STRATUM Operational Limits**: `Max Standoff Distance`
  (`maxGoToLocationDistance`) and `Max AOP Distance` (`maxAOPDistance`). Both
  take effect immediately.

### 7.9 Help

[HelpSettings.qml](../src/AppSettings/HelpSettings.qml) hosts a plain-language,
non-technical operator quick-start (AOP, Standoff, flight modes, camera view,
troubleshooting). Deliberately excludes RTSP / comm-link setup. This is a
placeholder; final help content is TBD.

---

## 8. Startup flow

```
main() → QGCApplication
       ├─ SettingsManager (facts hydrate from QSettings)
       ├─ ParameterManager  (per-vehicle, hydrates on link)
       ├─ MultiVehicleManager / LinkManager  (background)
       ├─ VideoManager (RTSP + SIYI socket)
       └─ TargetFetchManager (UDP socket bound eagerly)
                    ↓
   MainWindow.qml   Component.onCompleted:
       ├─ firstRunPromptManager.nextPrompt()
       └─ Force stratumProfile = 2 (Dagger) if not already
                    ↓
   Vehicle connect:
       ├─ Vehicle::_commonInit / PX4FirmwarePlugin::initializeVehicle
       │       └─ MAV_CMD_SET_MESSAGE_INTERVAL for ENGAGEMENT_STATUS (5 Hz)
       └─ Parameters download → EngagementController._armedVehicle unset,
                                ABRT_* known after first armAbort()
```

---

## 9. Extending STRATUM

### Add a new MAVLink message from PX4

1. Extend
   [stratum.xml](../src/MAVLink/mavlink_definitions/stratum.xml). Keep field
   order + names byte-identical to the firmware definition (CRC parity).
2. Rebuild — the mavgen step in `src/MAVLink/CMakeLists.txt` regenerates the
   headers.
3. Add a decoder in `Vehicle::_mavlinkMessageReceived` or a dedicated
   `FactGroup`. Expose to QML via `Q_PROPERTY`.

### Add a new operator command to PX4

1. If it fits a stock `MAV_CMD`, call `vehicle->sendMavCommand*` from a
   `Q_INVOKABLE` on `Vehicle`. Otherwise pick an id in the 3100x range and
   document it here.
2. Add a QML controller under `src/FlyView/` — mimic the shape of
   `StandoffController.qml`: profile guard, validation, single MAVLink call,
   local state latch on success.
3. Wire from `FlyViewToolStripActionList.qml` (right-side action strip) or the
   toolbar ribbon.

### Add a new setting

1. Add the fact definition to the appropriate
   `src/Settings/*.SettingsGroup.json` (label, default, min, units).
2. Add the matching `DEFINE_SETTINGFACT` / `DECLARE_SETTINGSFACT` in the
   header/source pair.
3. Expose it in the sidebar by adding a control entry to the relevant
   `src/AppSettings/pages/*.SettingsUI.json`.
4. Read it in QML as
   `QGroundControl.settingsManager.<group>.<fact>.rawValue` (or `.value` for
   type-coerced access).

### Change what the operator sees, not what the firmware does

1. Prefer `visible: false` with a `// STRATUM: hidden per operator UX spec. Flip
   back to <expr> to restore.` comment over deleting code.
2. Filter arrays (flight-mode whitelist) rather than mutate upstream lists.
3. Section-hide via `"showWhen": "false"` in the settings JSON instead of
   removing the entry.

---

## 10. Related documents

- [STANDOFF_PX4_CONTRACT_PROMPT.md](../STANDOFF_PX4_CONTRACT_PROMPT.md) — wire-level
  standoff contract with PX4.
- [FlyView_Override_Surface_Map.md](../../FlyView_Override_Surface_Map.md) — map
  of every QML override STRATUM patches into upstream QGC's Fly view.
- [UI-changes.md](../../UI-changes.md) — chronological log of operator-UX
  culls (hidden pages, hidden actions, whitelists).
- [BUILD-Windows.md](../../BUILD-Windows.md) / [INSTALL-Windows.md](../../INSTALL-Windows.md)
  — building the fork on Windows.
- [GIT-WORKFLOW.md](../../GIT-WORKFLOW.md) — branching + upstream-sync policy.

---

## 11. Glossary

| Term | Meaning |
|------|---------|
| **AOP** | Area of Operations — the operator-defined inclusion geofence polygon. Standoff targets must sit inside it. |
| **Standoff** | Target-relative orbit: aircraft holds at (distance, bearing) from a target coordinate, at a given height. |
| **Engagement** | Terminal run against the latched standoff target. Three variants: coordinate, vision, PN. |
| **PN** | Proportional Navigation — an intercept guidance law used by the PN Engagement mode. |
| **Abort** | Break-off flight mode that flies to a pre-armed `ABRT_*` destination. |
| **Safe Recovery** | Operator-facing label for `Return` (RTL) on STRATUM. |
| **Bridge (comp-id 191)** | Companion computer that executes the Dropper standoff contract. |
| **Pod (XC25)** | External target-designation appliance streaming its own status over UDP; not a MAVLink device. |
| **SIYI A2 mini** | Single-axis tilt gimbal controlled over UDP with the SIYI SDK v3 protocol. |
| **Companion tracker** | Vision tracker running on the airframe's mission computer, consuming `NEXAM_*` messages. |
