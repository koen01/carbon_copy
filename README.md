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
| Enable second printer | Show a second printer side by side | off |
| Emergency Stop | Show a stop button on the camera view | on |

The camera feed and MQTT ports are fixed by the printer's firmware (`8080` and `1883`) — no port fields needed.

---

## Controls

Same as `moonraker_viewer`: tap to toggle overlay/focus pane, pinch to zoom, double-tap to reset, gear icon for settings, D-pad/remote navigation throughout.

---

## Protocol

MQTT 3.1.1 — the printer itself is the broker (port `1883`), authenticated as `elegoo` / `<access code>`. Reconstructed from reverse-engineered community documentation, **not an official Elegoo spec** — see `CLAUDE.md` for details and known unknowns. If a status looks wrong on your printer, turn on the debug log overlay and compare against what `CentauriService` expects.

---

## Known limitations

- No print thumbnail (the thumbnail request/response shape wasn't documented confidently enough to implement safely in v1).
- `machine_status`/`sub_status` → UI state mapping is best-effort; please report any state that displays incorrectly on your printer.
- This has **not been tested against a physical Centauri Carbon 2** — it was built entirely from third-party protocol documentation. Please verify on your printer and expect to file (or fix) small protocol-mapping issues on first run.
