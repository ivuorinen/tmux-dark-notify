# Linux Desktop Environment Support — Design Spec

## Context

tmux-dark-notify is a tmux plugin that automatically switches themes when the system toggles between dark and light mode. It currently only supports macOS via the `dark-notify` CLI tool.

This design adds support for GNOME, KDE Plasma, and Pop!_OS COSMIC on Linux, while also adopting two valuable improvements from the upstream project (erikw/tmux-dark-notify): per-tmux-server process tracking and improved signal handling. We are diverging fully from upstream — this is now an independent project.

## Architecture

### File Structure

```
main.tmux                      # Entry point, daemon, theme switching, CLI
scripts/backend-macos.sh       # macOS backend wrapping dark-notify
scripts/backend-linux.sh       # Linux backend with DE fallback chain
```

### Backend Interface

Each backend script defines three functions that `main.tmux` calls:

- **`backend_detect_mode`** — Returns `"dark"` or `"light"` for the current system appearance. Used for initial theme set on startup.
- **`backend_monitor_changes <cmd> [args…]`** — Blocks and invokes `<cmd> [args…] dark` or `<cmd> [args…] light` whenever the system appearance changes. The callback is passed as argv (command + fixed args) to avoid word-splitting issues with paths containing spaces.
- **`backend_check_deps`** — Verifies that the backend's required tools are available and returns a non-zero status with an error message if they are not.

### Platform Dispatch

In `main.tmux`, after determining `SCRIPT_DIR`:

```bash
case "$OSTYPE" in
  darwin*) source "$SCRIPT_DIR/scripts/backend-macos.sh" ;;
  linux*)  source "$SCRIPT_DIR/scripts/backend-linux.sh" ;;
  *)       echo "Unsupported platform: $OSTYPE" >&2; exit 1 ;;
esac
```

## macOS Backend (`scripts/backend-macos.sh`)

Wraps the existing `dark-notify` integration:

- `backend_detect_mode`: Runs `dark-notify -e` or queries defaults to get current mode.
- `backend_monitor_changes`: Runs `dark-notify -c <callback>` in a loop (current behavior, extracted).

Dependencies: `dark-notify` (via Homebrew), Bash.

## Linux Backend (`scripts/backend-linux.sh`)

### Detection Fallback Chain

The backend probes available tools **once at startup** and selects a detection method. The same method is used for both `backend_detect_mode` and `backend_monitor_changes`.

Priority order:

1. **Freedesktop portal** — `org.freedesktop.appearance.color-scheme` via `dbus-send`. Works across GNOME, KDE (with portal support), and any DE implementing the XDG desktop portal.
2. **GNOME** — `gsettings get org.gnome.desktop.interface color-scheme`. Values: `'prefer-dark'` = dark, everything else = light.
3. **KDE** — Uses the freedesktop portal (`dbus-send` on `org.freedesktop.portal.Settings`) when available, with a fallback to reading `~/.config/kdeglobals` (`ColorScheme=` key) to infer dark/light from the colour scheme name.
4. **COSMIC** — Reads `~/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark`. Values: `true` = dark, `false` = light.

### Monitoring Strategies

| Method | Monitor command | Notes |
|--------|----------------|-------|
| Freedesktop portal | `dbus-monitor` on `org.freedesktop.portal.Settings.SettingChanged` signal filtered to `org.freedesktop.appearance` + `color-scheme` | Most universal |
| GNOME | `gsettings monitor org.gnome.desktop.interface color-scheme` | Emits new value on each change |
| KDE | `dbus-monitor` on `org.freedesktop.portal.Settings.SettingChanged` signal (same as portal method); kdeglobals read only for initial detection fallback | Needs portal support |
| COSMIC | `inotifywait -m` on the config file, with fallback to 5-second polling if `inotifywait` is not installed | File-based detection |

### Detection Implementation

```bash
# Determine which method to use (called once at startup)
_linux_select_backend() {
  if command -v dbus-send &>/dev/null; then
    local result
    result=$(dbus-send --session --print-reply \
      --dest=org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop \
      org.freedesktop.portal.Settings.Read \
      string:'org.freedesktop.appearance' string:'color-scheme' 2>/dev/null) && {
      LINUX_BACKEND="portal"
      return
    }
  fi

  if command -v gsettings &>/dev/null && \
     gsettings get org.gnome.desktop.interface color-scheme &>/dev/null; then
    LINUX_BACKEND="gnome"
    return
  fi

  if command -v dbus-send &>/dev/null && \
     dbus-send --session --print-reply --dest=org.kde.KWin \
       /org/kde/KWin org.kde.KWin.currentColorScheme 2>/dev/null; then
    LINUX_BACKEND="kde"
    return
  fi

  local cosmic_config="${HOME}/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"
  if [[ -f "$cosmic_config" ]]; then
    LINUX_BACKEND="cosmic"
    return
  fi

  echo "No supported dark mode detection method found." >&2
  exit 1
}
```

## Per-Server Process Tracking

Adopted from upstream, adapted for cross-platform:

- PID file key derived from MD5 hash of the tmux socket path (`${TMUX%%,*}`)
- Uses `md5sum` on Linux, `md5 -qs` on macOS, with a `tr`-based sanitization fallback
- Each tmux server gets its own daemon instance and PID file
- Stale PID files detected via `kill -0` and cleaned up automatically

```bash
TMUX_SOCKET="${TMUX%%,*}"
if command -v md5sum &>/dev/null; then
  PID_FILE_KEY=$(echo -n "$TMUX_SOCKET" | md5sum | cut -d' ' -f1)
elif command -v md5 &>/dev/null; then
  PID_FILE_KEY=$(md5 -qs "$TMUX_SOCKET")
else
  PID_FILE_KEY=$(echo -n "$TMUX_SOCKET" | tr '/' '_')
fi
PID_FILE="${TMUX_STATE_DIR}/tmux-dark-notify-${PID_FILE_KEY}.pid"
```

## Signal Handling

Improved from current implementation (adopted from upstream pattern):

```bash
daemon_mode() {
  # ... PID file creation, dependency checks ...

  trap cleanup EXIT TERM HUP INT

  while :; do
    backend_monitor_changes "$0" "--theme" &
    MONITOR_PID=$!
    wait "$MONITOR_PID" || true
    MONITOR_PID=
    sleep 1  # Throttle restarts
  done
}

cleanup() {
  rm -f "$PID_FILE"
  [[ -n "${MONITOR_PID-}" ]] && kill "$MONITOR_PID" 2>/dev/null || true
}
```

Backgrounding the monitor and using `wait` allows signals to be caught immediately rather than blocking until the monitor process exits.

## Dependency Matrix

| Platform | Required | Optional |
|----------|----------|----------|
| macOS | Bash, Homebrew, `dark-notify`, tmux | — |
| Linux (freedesktop portal) | Bash, `dbus-send`, `dbus-monitor`, tmux | — |
| Linux (GNOME fallback) | Bash, `gsettings`, tmux | — |
| Linux (KDE fallback) | Bash, `dbus-send`, `dbus-monitor`, tmux | — |
| Linux (COSMIC fallback) | Bash, tmux | `inotifywait` (for instant detection; falls back to polling) |

No new compiled dependencies on Linux — all tools ship with their respective desktop environments.

## Changes to Existing Files

### main.tmux

- Remove macOS-specific code (extract to backend-macos.sh)
- Add platform dispatch (`case "$OSTYPE"`)
- Replace direct `dark-notify` calls with `backend_monitor_changes`
- Replace lock file with per-server PID file tracking
- Improve signal handling (background + wait pattern)
- Keep: theme switching logic, CLI parsing, usage display

### README.md

- Update title/description to reflect cross-platform support
- Add Linux requirements section per DE
- Add Linux installation instructions (same tpm process, different dependencies)
- Add Linux configuration examples
- Keep all existing macOS documentation

### CLAUDE.md

- Update to reflect new multi-file architecture and backend system

## Verification

1. **macOS**: Confirm existing functionality unchanged — toggle system appearance, verify theme switches
2. **Linux GNOME**: Set `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`, verify theme switches
3. **Linux KDE**: Toggle dark mode in system settings, verify theme switches
4. **Linux COSMIC**: Toggle dark mode in COSMIC settings, verify theme switches
5. **Per-server**: Run two tmux servers (`tmux -L server1`, `tmux -L server2`), verify independent daemon instances
6. **Cleanup**: Kill tmux servers, verify PID files are removed
7. **Fallback chain**: On GNOME, test with and without `xdg-desktop-portal-gnome` to verify portal → gsettings fallback
