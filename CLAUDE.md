# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

tmux-dark-notify is a tmux plugin that automatically switches themes when the system toggles between dark and light mode. It supports macOS (via `dark-notify`) and Linux (GNOME, KDE Plasma, COSMIC via freedesktop portal with DE-specific fallbacks).

## Architecture

### File Structure

```
main.tmux                   # Entry point, daemon, theme switching, CLI, platform dispatch
scripts/backend-macos.sh    # macOS backend wrapping dark-notify
scripts/backend-linux.sh    # Linux backend with DE fallback chain
```

### Execution Modes

The script operates in three modes, determined by command-line arguments:

- **Entry point** (no args): Default when tmux loads the plugin via tpm. Checks for an existing daemon via PID file, launches one in the background if needed.
- **Daemon** (`--daemon`): Runs the platform backend's monitor in a loop, which calls back into the script with `--theme light` or `--theme dark` when the system appearance changes.
- **Theme** (`--theme <mode>`): Sources the appropriate tmux theme config file and creates a symlink at `~/.local/state/tmux/tmux-dark-notify-theme.conf` for fallback loading.

### Backend Interface

Each platform backend (`scripts/backend-*.sh`) defines three functions:
- `backend_detect_mode` — Returns `"dark"` or `"light"` for current system appearance
- `backend_monitor_changes <callback>` — Blocks and invokes callback on appearance change
- `backend_check_deps` — Validates required tools are available

### Linux Detection Fallback Chain

`scripts/backend-linux.sh` probes once at source-time and selects: freedesktop portal → GNOME gsettings → KDE → COSMIC config file.

### Key Mechanisms

- **Per-server PID files** (`~/.local/state/tmux/tmux-dark-notify-<hash>.pid`): One daemon per tmux server, keyed by MD5 of the tmux socket path.
- **Tmux options**: `@dark-notify-theme-path-light` and `@dark-notify-theme-path-dark` configure theme file paths.
- **State directory**: `${XDG_STATE_HOME:-$HOME/.local/state}/tmux/` for PID files and theme symlink.

## Development

**No build system, tests, CI, or linter configuration exists.** Changes are verified manually.

### Code Style
- `.editorconfig`: 2-space indentation, LF line endings, UTF-8, trim trailing whitespace
- Bash strict mode: `set -o errexit`, `set -o pipefail`
- Vim modeline in script header: `ft=bash ts=2 sw=2 tw=80`

### Debugging
- Set `TRACE=1` (or `true`/`yes`/`t`/`y`) to enable `set -o xtrace` for verbose execution tracing.

### Dependencies

**macOS:** Bash, Homebrew, `dark-notify` (`brew install cormacrelf/tap/dark-notify`), tmux

**Linux:** Bash, tmux, plus one of:
- `dbus-send` + `dbus-monitor` (freedesktop portal / KDE)
- `gsettings` (GNOME)
- Optionally `inotifywait` (COSMIC, for instant detection)
