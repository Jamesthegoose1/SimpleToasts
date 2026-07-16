# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-14

### Added

- Initial release.
- Five severities (`success`, `info`, `warn`, `error`, `secondary`) with per-severity
  colours, icons, and sounds; `customTheme` override per toast.
- Six screen positions with a `maxVisible` cap per position.
- Auto-dismiss (`life`), `sticky` toasts, close button, pause-on-hover/hold.
- Slide + fade animations with smooth neighbour reflow (`TweenService`).
- Stacked piles (on by default): hover/tap to expand, pile-wide timer pause,
  `expandedCount` setting.
- Opt-in sound effects (`soundEnabled`, `defaultVolume`, per-toast `sound`, `silent`,
  `volume`).
- Runtime configuration via `Toast.configure()`.
- Server → client bridge: `Toast.notify(player, message)` and
  `Toast.notifyAll(message)`.
- Keyboard-driven demo place (`demo.project.json`).
