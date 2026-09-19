# Carbon Copy

A Flutter app that shows your **Elegoo Centauri Carbon 2**'s MJPEG camera feed fullscreen with a live print status overlay. Connects directly over the printer's **LAN-only protocol** — no Elegoo account, no cloud. Read-only — no pause/resume/cancel controls beyond an optional emergency stop.

A sibling project to [`moonraker_viewer`](../moonraker_viewer) — same UI/UX, different printer and transport.

---

## Features

- Fullscreen MJPEG camera feed in landscape immersive mode
- Pinch-to-zoom + pan (double-tap to reset)
- Tap to toggle overlay visibility
- Live status overlay over MQTT:
  - Printer state, filename, ETA wall clock
  - Hotend and bed temperatures (with heating indicator)
  - Progress bar, elapsed / remaining time
  - Layer count (`current / total`)
  - Print phase next to the state (e.g. "PRINTING · AUTO LEVELING", "PREHEATING NOZZLE")
  - Chamber temperature
  - Optional fan chips: model, assistance and case fan speed (%)
- **Canvas overlay** — loaded filament (color, type, name) for each Canvas tray, with the active tray highlighted (toggleable in Settings)
- **Split-screen dual-printer mode** — two printers side by side; tap a pane to focus it full-screen
- **Debug log overlay** — last 15 raw messages from the printer, bottom-right corner (toggleable in Settings) — useful for verifying the (reverse-engineered) protocol against your printer
- Serial number auto-detected via UDP discovery on save
- Keep screen on toggle
- Auto-reconnect on connection loss
- Emergency stop button (stops the current print)

---

## Setup

```sh
flutter pub get
flutter run
```

On your printer, enable **LAN Only Mode** and note the access code shown on its touchscreen (Settings → LAN Only Mode).

---

## First run

On first launch the Settings screen opens automatically:

| Setting | Description | Default |
|---|---|---|
| Printer host | IP address of the printer on your LAN | — |
| Access code | LAN access code from the printer's touchscreen | — |
| Serial number | Auto-detected on save via UDP; fill in manually only if that fails | — |
| Keep screen on | Prevent the display from sleeping | on |
| Show debug log overlay | Show last 15 raw printer messages bottom-right | off |
| Show canvas overlay | Show the loaded filament for each Canvas tray, bottom-left | off |
| Show fan chips | Show model / assistance / case fan speeds in the bottom bar | off |
| Enable second printer | Show a second printer side by side | off |
| Emergency Stop | Show a stop button on the camera view | on |

The camera feed and MQTT ports are fixed by the printer's firmware (`8080` and `1883`) — no port fields needed.

---

## Controls

Same as `moonraker_viewer`: tap to toggle overlay/focus pane, pinch to zoom, double-tap to reset, gear icon for settings, D-pad/remote navigation throughout.

---

## Protocol

MQTT 3.1.1 — the printer itself is the broker (port `1883`), authenticated as `elegoo` / `<access code>`. Reconstructed from reverse-engineered community documentation, **not an official Elegoo spec** — see `CLAUDE.md` for details and known unknowns. Status/sub-status code names and method numbers come from the [elegoo-web](https://github.com/runnane/elegoo-web) project ([`types.ts`](https://github.com/runnane/elegoo-web/blob/main/src/types.ts), [`printer-state.ts`](https://github.com/runnane/elegoo-web/blob/main/src/printer-state.ts)). If a status looks wrong on your printer, turn on the debug log overlay and compare against what `CentauriService` expects.

---

## Known limitations

- Tested against a physical Centauri Carbon 2 (with a Canvas, OTA firmware `02.01.00.00`), but the protocol is still community-documented rather than an official Elegoo spec, so other firmware versions may report things differently.
- No print thumbnail — the thumbnail request/response (method `1045`) isn't implemented yet.
- Print state comes from the printer's `print_status.state` / `machine_status.status`; the phase label (e.g. "Auto Leveling") uses the community-published `sub_status` table. Codes missing from that table show as "Preparing" until the first layer. Please report any state or phase that displays incorrectly on your printer.
