# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter mobile app (iOS + Android) that displays an Elegoo Centauri Carbon 2's MJPEG camera feed fullscreen with a live overlay of print status, connecting over the printer's **LAN-only protocol** (no cloud, no Elegoo account). This is a sibling project to `moonraker_viewer` — same UI/UX, different printer and transport.

## Commands

```bash
flutter pub get          # install dependencies
flutter run               # run on connected device/emulator
flutter build apk        # build Android APK
flutter build ios        # build iOS
flutter test             # run tests
flutter test test/widget_test.dart --plain-name "<test name>"   # run a single test
dart format .            # format Dart code
flutter analyze          # lint
dart run flutter_launcher_icons   # regenerate Android icons from assets/app_icon*.png (config in pubspec.yaml)
```

Only `test/widget_test.dart` exists; there are no tests for the MQTT service or state parsing. Lints come from `flutter_lints` with no custom rules.

## Architecture

Source files live under `lib/`:

```
lib/
  main.dart                        # entry point, orientation lock, immersive mode, theme
  models/printer_state.dart        # data model + CC2 status parsing
  services/centauri_service.dart   # MQTT client (the LAN protocol)
  services/discovery_service.dart  # UDP serial-number discovery
  screens/viewer_screen.dart       # top-level screen; single or split layout
  screens/settings_screen.dart
  widgets/printer_pane.dart        # self-contained pane for one printer (feed + overlay + service)
  widgets/info_overlay.dart
  widgets/estop_button.dart
  widgets/walkthrough_overlay.dart
```

**Data flow:**

1. `SettingsScreen` saves host/access code (and optional second printer) to `SharedPreferences`. On save, it runs UDP discovery (`DiscoveryService`) to resolve the printer's serial number automatically; a manual override field exists for when discovery fails.
2. `ViewerScreen` loads those prefs on init, decides between single-pane and split-screen layout, and renders one or two `PrinterPane` widgets. A printer only counts as "configured" once both host and serial number are known.
3. `PrinterPane` owns a `CentauriService` instance, points the `Mjpeg` widget at the fixed camera URL (`http://<host>:8080/?action=stream`), manages the 15-line debug-log buffer, and holds the `TransformationController` for zoom/pan.
4. `CentauriService` connects via MQTT 3.1.1 on port 1883 — **the printer itself is the broker**. Auth is username `elegoo` / password = the LAN access code. After connecting it registers (publish to `elegoo/<sn>/api_register`, subscribe to the matching `register_response` topic), then subscribes to `elegoo/<sn>/api_status` for delta status pushes and `elegoo/<sn>/<clientId>/api_response` for command replies. It sends an app-level `{"type":"PING"}` heartbeat every 10s (in addition to MQTT's own keepalive), refreshes full status (method `1002`) every 20s, and enables the camera (method `1042`) after every (re)connect.
5. `InfoOverlay` consumes `PrinterState` and shows temperatures, progress, elapsed/remaining time, ETA wall clock, and layer count. The debug-log overlay (last 15 raw MQTT payloads, toggle in Settings) stands in for the original app's Klipper console — CC2 has no G-code console, but the raw feed is invaluable for verifying the protocol against a real printer.

**Key implementation notes:**

- **The CC2 protocol here is reverse-engineered from community docs (elegoo-web, elegoo-homeassistant's `CC2_PROTOCOL.md`, Centauri-Dashboard), not an official spec.** In particular, the exact `machine_status`/`sub_status` → UI-state code table (`PrinterState._mapState`) and the thumbnail response shape are best-effort. If a status looks wrong against a real printer, turn on the debug-log overlay (Settings → "Show debug log overlay") and compare the raw payloads against `CentauriService._extractStatusPayload` / `PrinterState.fromCentauri`.
- No print thumbnail in this fork (v1) — the thumbnail request/response shape (method `1045`) wasn't confidently documented enough to implement without likely breaking silently. `InfoOverlay` already renders a placeholder icon when `thumbnailUrl` is null.
- No state management library — plain Dart streams + `setState`, mirroring `moonraker_viewer`.
- Auto-reconnect: 3-second retry loop on MQTT disconnect, same shape as `MoonrakerService` in the sibling project.
- Keepalive: MQTT protocol-level keepalive (30s) plus the app-level 10s PING the printer's firmware expects.
- App lifecycle: `PrinterPane` observes lifecycle and calls `CentauriService.suspend()`/`resume()` — the MQTT connection and timers are torn down while the app is backgrounded and reconnected on resume.
- Self-healing feed: on every MQTT (re)connect, `PrinterPane` bumps `_feedEpoch` (used as the `Mjpeg` widget key) to restart a stalled/errored MJPEG stream, and the camera-enable command (`1042`) is resent.
- `main.dart` locks orientation to landscape and enables `SystemUiMode.immersiveSticky`.
- **Split-screen mode**: identical to `moonraker_viewer` — two `PrinterPane`s in a `Row`, tap/D-pad-select to focus full-screen.
- **E-Stop button**: sends `STOP_PRINT` (method `1022`) over MQTT rather than an HTTP emergency-stop call — CC2's LAN protocol has no lower-level hardware e-stop endpoint in the documented command set, so this is "stop the current print immediately", same panic-button intent as the original.
- Ports are fixed by the printer's firmware, unlike Moonraker's configurable port: MQTT `1883`, camera `8080`, UDP discovery `52700`. Settings has no port field.
- Cleartext HTTP/TCP is required for LAN printer connections — `android:usesCleartextTraffic="true"` on Android; iOS raw sockets aren't subject to ATS, but `NSLocalNetworkUsageDescription` is set in `Info.plist` since iOS 14+ prompts for local-network access.
- SharedPreferences keys: `printer_host`, `printer_access_code`, `printer_sn`, `keep_screen_on`, `show_debug_log`, `second_printer_enabled`, `printer_host_2`, `printer_access_code_2`, `printer_sn_2`, `estop_enabled`, `estop_hold_ms`, `onboarding_seen`.
