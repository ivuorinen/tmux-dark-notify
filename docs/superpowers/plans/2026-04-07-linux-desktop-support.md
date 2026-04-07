# Linux Desktop Environment Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GNOME, KDE Plasma, and Pop!_OS COSMIC dark/light mode support to tmux-dark-notify, while adopting per-server PID tracking and improved signal handling from upstream.

**Architecture:** Platform-specific backends sourced by main.tmux via `$OSTYPE` dispatch. macOS keeps `dark-notify`, Linux uses a freedesktop portal → GNOME → KDE → COSMIC fallback chain. Per-server PID files replace the single lock file. Monitor processes are backgrounded with `wait` for clean signal handling.

**Tech Stack:** Bash, dbus-send, dbus-monitor, gsettings, inotifywait (optional)

**Spec:** `docs/superpowers/specs/2026-04-07-linux-desktop-support-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `main.tmux` | Modify | Entry point, daemon, theme switching, CLI, platform dispatch, per-server PID tracking |
| `scripts/backend-macos.sh` | Create | macOS backend: `backend_detect_mode`, `backend_monitor_changes` wrapping `dark-notify` |
| `scripts/backend-linux.sh` | Create | Linux backend: fallback chain detection + monitoring for portal/GNOME/KDE/COSMIC |
| `README.md` | Modify | Add Linux support docs, update description, keep macOS docs |
| `CLAUDE.md` | Modify | Update architecture and dependency sections |

---

### Task 1: Create feature branch and scripts directory

**Files:**
- Create: `scripts/` directory

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b feat/linux-desktop-support
```

- [ ] **Step 2: Create scripts directory**

```bash
mkdir -p scripts
```

---

### Task 2: Create macOS backend (`scripts/backend-macos.sh`)

Extract macOS-specific logic from `main.tmux` into the backend interface.

**Files:**
- Create: `scripts/backend-macos.sh`

- [ ] **Step 1: Write the macOS backend**

```bash
#!/usr/bin/env bash
# macOS backend for tmux-dark-notify
# Uses dark-notify (https://github.com/cormacrelf/dark-notify) to detect
# and monitor system appearance changes.

# Returns "dark" or "light" for current system appearance.
backend_detect_mode() {
  local raw
  raw=$(defaults read -g AppleInterfaceStyle 2>/dev/null) || true
  if [[ "$raw" == "Dark" ]]; then
    echo "dark"
  else
    echo "light"
  fi
}

# Blocks and calls <callback> with "dark" or "light" on appearance change.
# Usage: backend_monitor_changes "/path/to/script --theme"
backend_monitor_changes() {
  local callback="$1"
  dark-notify -c "$callback"
}

# Validate that required dependencies are available.
backend_check_deps() {
  # If BREW_PREFIX is already set, skip calling brew shellenv
  if [[ -z "${BREW_PREFIX-}" ]]; then
    if ! command -v brew &>/dev/null; then
      echo "Could not find brew(1) in \$PATH" >&2
      return 1
    fi
    eval "$(brew shellenv)"
  fi

  if ! command -v dark-notify &>/dev/null; then
    echo "Could not find dark-notify(1) in \$PATH" >&2
    echo "Install with: brew install cormacrelf/tap/dark-notify" >&2
    return 1
  fi
}
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/backend-macos.sh
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n scripts/backend-macos.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

---

### Task 3: Create Linux backend (`scripts/backend-linux.sh`)

Implements the freedesktop portal → GNOME → KDE → COSMIC fallback chain.

**Files:**
- Create: `scripts/backend-linux.sh`

- [ ] **Step 1: Write the Linux backend**

```bash
#!/usr/bin/env bash
# Linux backend for tmux-dark-notify
# Supports: freedesktop portal, GNOME, KDE Plasma, Pop!_OS COSMIC
# Detection method is probed once at source-time via _linux_select_backend.

LINUX_BACKEND=""

# --- Portal (freedesktop.org) -------------------------------------------

_portal_detect_mode() {
  local result
  result=$(dbus-send --session --print-reply \
    --dest=org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings.Read \
    string:'org.freedesktop.appearance' string:'color-scheme' 2>/dev/null)
  if [[ "$result" == *"uint32 1"* ]]; then
    echo "dark"
  else
    echo "light"
  fi
}

_portal_monitor_changes() {
  local callback="$1"
  dbus-monitor --session \
    "type='signal',interface='org.freedesktop.portal.Settings',member='SettingChanged',arg0='org.freedesktop.appearance',arg1='color-scheme'" 2>/dev/null |
  while read -r line; do
    if [[ "$line" == *"uint32"* ]]; then
      local value
      value=$(echo "$line" | grep -o 'uint32 [0-9]*' | tail -1 | cut -d' ' -f2)
      if [[ "$value" == "1" ]]; then
        $callback dark
      else
        $callback light
      fi
    fi
  done
}

# --- GNOME ---------------------------------------------------------------

_gnome_detect_mode() {
  local result
  result=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)
  if [[ "$result" == *"prefer-dark"* ]]; then
    echo "dark"
  else
    echo "light"
  fi
}

_gnome_monitor_changes() {
  local callback="$1"
  gsettings monitor org.gnome.desktop.interface color-scheme 2>/dev/null |
  while read -r _key value; do
    if [[ "$value" == *"prefer-dark"* ]]; then
      $callback dark
    else
      $callback light
    fi
  done
}

# --- KDE Plasma ----------------------------------------------------------

_kde_detect_mode() {
  local result
  result=$(dbus-send --session --print-reply \
    --dest=org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings.Read \
    string:'org.freedesktop.appearance' string:'color-scheme' 2>/dev/null)
  if [[ "$result" == *"uint32 1"* ]]; then
    echo "dark"
  else
    # Fallback: read kdeglobals config file
    local kde_config="${HOME}/.config/kdeglobals"
    if [[ -f "$kde_config" ]]; then
      local scheme
      scheme=$(grep -i "^ColorScheme=" "$kde_config" 2>/dev/null | cut -d= -f2)
      if [[ "$scheme" == *"[Dd]ark"* ]]; then
        echo "dark"
      else
        echo "light"
      fi
    else
      echo "light"
    fi
  fi
}

_kde_monitor_changes() {
  local callback="$1"
  dbus-monitor --session \
    "type='signal',interface='org.freedesktop.portal.Settings',member='SettingChanged',arg0='org.freedesktop.appearance',arg1='color-scheme'" 2>/dev/null |
  while read -r line; do
    if [[ "$line" == *"uint32"* ]]; then
      local value
      value=$(echo "$line" | grep -o 'uint32 [0-9]*' | tail -1 | cut -d' ' -f2)
      if [[ "$value" == "1" ]]; then
        $callback dark
      else
        $callback light
      fi
    fi
  done
}

# --- COSMIC (Pop!_OS) ----------------------------------------------------

_COSMIC_CONFIG="${HOME}/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"

_cosmic_detect_mode() {
  if [[ -f "$_COSMIC_CONFIG" ]]; then
    local value
    value=$(cat "$_COSMIC_CONFIG" 2>/dev/null)
    if [[ "$value" == "true" ]]; then
      echo "dark"
    else
      echo "light"
    fi
  else
    echo "light"
  fi
}

_cosmic_monitor_changes() {
  local callback="$1"
  if command -v inotifywait &>/dev/null; then
    inotifywait -m -e modify "$_COSMIC_CONFIG" 2>/dev/null |
    while read -r _dir _events _file; do
      local mode
      mode=$(_cosmic_detect_mode)
      $callback "$mode"
    done
  else
    # Polling fallback when inotifywait is not available
    local last_mode
    last_mode=$(_cosmic_detect_mode)
    while :; do
      sleep 5
      local current_mode
      current_mode=$(_cosmic_detect_mode)
      if [[ "$current_mode" != "$last_mode" ]]; then
        last_mode="$current_mode"
        $callback "$current_mode"
      fi
    done
  fi
}

# --- Backend selection ---------------------------------------------------

_linux_select_backend() {
  # 1. Try freedesktop portal
  if command -v dbus-send &>/dev/null; then
    dbus-send --session --print-reply \
      --dest=org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop \
      org.freedesktop.portal.Settings.Read \
      string:'org.freedesktop.appearance' string:'color-scheme' &>/dev/null && {
      LINUX_BACKEND="portal"
      return
    }
  fi

  # 2. Try GNOME gsettings
  if command -v gsettings &>/dev/null && \
     gsettings get org.gnome.desktop.interface color-scheme &>/dev/null; then
    LINUX_BACKEND="gnome"
    return
  fi

  # 3. Try KDE (via portal or config file)
  if command -v dbus-send &>/dev/null; then
    local kde_config="${HOME}/.config/kdeglobals"
    if [[ -f "$kde_config" ]]; then
      LINUX_BACKEND="kde"
      return
    fi
  fi

  # 4. Try COSMIC
  if [[ -f "$_COSMIC_CONFIG" ]]; then
    LINUX_BACKEND="cosmic"
    return
  fi

  echo "No supported dark mode detection method found on this system." >&2
  echo "Supported: freedesktop portal, GNOME, KDE Plasma, COSMIC" >&2
  exit 1
}

# --- Public interface (called by main.tmux) ------------------------------

backend_detect_mode() {
  case "$LINUX_BACKEND" in
    portal) _portal_detect_mode ;;
    gnome)  _gnome_detect_mode ;;
    kde)    _kde_detect_mode ;;
    cosmic) _cosmic_detect_mode ;;
  esac
}

backend_monitor_changes() {
  local callback="$1"
  case "$LINUX_BACKEND" in
    portal) _portal_monitor_changes "$callback" ;;
    gnome)  _gnome_monitor_changes "$callback" ;;
    kde)    _kde_monitor_changes "$callback" ;;
    cosmic) _cosmic_monitor_changes "$callback" ;;
  esac
}

backend_check_deps() {
  case "$LINUX_BACKEND" in
    portal|kde)
      if ! command -v dbus-send &>/dev/null; then
        echo "dbus-send is required but not found." >&2
        return 1
      fi
      if ! command -v dbus-monitor &>/dev/null; then
        echo "dbus-monitor is required but not found." >&2
        return 1
      fi
      ;;
    gnome)
      if ! command -v gsettings &>/dev/null; then
        echo "gsettings is required but not found." >&2
        return 1
      fi
      ;;
    cosmic)
      if ! command -v inotifywait &>/dev/null; then
        echo "Warning: inotifywait not found, falling back to polling." >&2
        echo "Install inotify-tools for instant detection." >&2
      fi
      ;;
  esac
}

# Select backend at source time
_linux_select_backend
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/backend-linux.sh
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n scripts/backend-linux.sh
```

Note: This will fail on macOS (no dbus-send) since `_linux_select_backend` runs at source time. That's expected — the file is only sourced on Linux. Syntax check with `bash -n` only parses, doesn't execute, so it should pass.

---

### Task 4: Refactor main.tmux

Replace macOS-specific code with platform dispatch, per-server PID tracking, and improved signal handling. Keep theme switching, CLI parsing, and usage display.

**Files:**
- Modify: `main.tmux` (full rewrite)

- [ ] **Step 1: Write the refactored main.tmux**

```bash
#!/usr/bin/env bash
# tmux-dark-notify - Make tmux's theme follow system dark/light mode
#
# Supports macOS (via dark-notify) and Linux (GNOME, KDE, COSMIC).
#
# This unified script handles all functionality:
# - Entry point: Launch daemon if not running
# - Daemon mode: Run backend monitor loop
# - Theme mode: Switch tmux theme
#
# vim: ft=bash ts=2 sw=2 tw=80

set -o errexit
set -o pipefail
[[ "${TRACE-0}" =~ ^1|t|y|true|yes$ ]] && set -o xtrace

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# State directory (XDG compliant)
TMUX_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"

# Theme configuration
OPTION_THEME_LIGHT="@dark-notify-theme-path-light"
OPTION_THEME_DARK="@dark-notify-theme-path-dark"

# Per-server PID tracking
MONITOR_PID=

# =============================================================================
# PLATFORM DISPATCH
# =============================================================================

case "$OSTYPE" in
  darwin*) source "$SCRIPT_DIR/scripts/backend-macos.sh" ;;
  linux*)  source "$SCRIPT_DIR/scripts/backend-linux.sh" ;;
  *)
    echo "Unsupported platform: $OSTYPE" >&2
    exit 1
    ;;
esac

# =============================================================================
# PID FILE MANAGEMENT
# =============================================================================

_compute_pid_file() {
  local tmux_socket="${TMUX%%,*}"
  local pid_key

  if command -v md5sum &>/dev/null; then
    pid_key=$(echo -n "$tmux_socket" | md5sum | cut -d' ' -f1)
  elif command -v md5 &>/dev/null; then
    pid_key=$(md5 -qs "$tmux_socket")
  else
    pid_key=$(echo -n "$tmux_socket" | tr '/' '_')
  fi

  echo "${TMUX_STATE_DIR}/tmux-dark-notify-${pid_key}.pid"
}

create_pid_file() {
  local pid_file="$1"

  if [[ ! -d "$TMUX_STATE_DIR" ]]; then
    if ! mkdir -p "$TMUX_STATE_DIR"; then
      echo "Failed to create state directory: $TMUX_STATE_DIR" >&2
      return 1
    fi
  fi

  echo $$ > "$pid_file"
}

check_pid_file() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1

  local existing_pid
  existing_pid=$(cat "$pid_file" 2>/dev/null)

  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    return 0  # Process is running
  fi

  # Stale PID file
  rm -f "$pid_file"
  return 1
}

# =============================================================================
# THEME MANAGEMENT
# =============================================================================

tmux_get_option() {
  local option=$1
  local opt_val
  opt_val=$(tmux show-option -gqv "$option")
  if [[ -z "$opt_val" ]]; then
    echo "Required tmux plugin option '$option' not set!" >&2
    exit 1
  fi
  echo "$opt_val"
}

tmux_set_theme_mode() {
  local mode="$1"

  if [[ ! -d "$TMUX_STATE_DIR" ]]; then
    if ! mkdir -p "$TMUX_STATE_DIR"; then
      echo "Failed to create state directory: $TMUX_STATE_DIR" >&2
      exit 3
    fi
  fi

  local theme_path
  if [[ "$mode" = "dark" ]]; then
    theme_path=$(tmux_get_option "$OPTION_THEME_DARK")
  else
    theme_path=$(tmux_get_option "$OPTION_THEME_LIGHT")
  fi

  # Expand variables like $HOME in theme path
  theme_path=$(eval echo "$theme_path")
  if [[ ! -r "$theme_path" ]]; then
    echo "The configured $mode theme is not readable: $theme_path" >&2
    exit 2
  fi

  local tmux_theme_link="$TMUX_STATE_DIR/tmux-dark-notify-theme.conf"

  if ! tmux source-file "$theme_path"; then
    echo "Failed to source tmux theme file: $theme_path" >&2
    exit 3
  fi
  if ! ln -sf "$theme_path" "$tmux_theme_link"; then
    echo "Failed to create theme symlink: $tmux_theme_link" >&2
    exit 3
  fi
}

# =============================================================================
# EXECUTION MODES
# =============================================================================

show_usage() {
  cat <<EOF
tmux-dark-notify - Make tmux's theme follow system dark/light mode

Usage:
  $SCRIPT_NAME                 Launch daemon (default mode)
  $SCRIPT_NAME --daemon        Run monitor daemon loop
  $SCRIPT_NAME --theme <mode>  Set theme (light|dark)
  $SCRIPT_NAME --help          Show this help

Examples:
  $SCRIPT_NAME --theme dark    Set dark theme
  $SCRIPT_NAME --theme light   Set light theme
EOF
}

cleanup() {
  [[ -n "${PID_FILE-}" ]] && rm -f "$PID_FILE"
  [[ -n "${MONITOR_PID-}" ]] && kill "$MONITOR_PID" 2>/dev/null || true
}

entry_point_mode() {
  local pid_file
  pid_file=$(_compute_pid_file)

  if check_pid_file "$pid_file"; then
    exit 0
  fi

  nohup "$0" --daemon </dev/null >/dev/null 2>&1 &
  sleep 0.1
}

daemon_mode() {
  PID_FILE=$(_compute_pid_file)

  if check_pid_file "$PID_FILE"; then
    if [[ ! "${TMUX-}" ]]; then
      echo "$SCRIPT_NAME daemon is already running for this tmux server."
    fi
    exit 0
  fi

  if ! create_pid_file "$PID_FILE"; then
    if [[ ! "${TMUX-}" ]]; then
      echo "Failed to create PID file. Another instance may be starting." >&2
    fi
    exit 1
  fi

  trap cleanup EXIT TERM HUP INT

  if ! backend_check_deps; then
    exit 1
  fi

  while :; do
    backend_monitor_changes "$0 --theme" &
    MONITOR_PID=$!
    wait "$MONITOR_PID" || true
    MONITOR_PID=
    sleep 1
  done
}

theme_mode() {
  local mode="$1"

  if [[ -z "$mode" ]] || [[ "$mode" == "-h" ]] || [[ "$mode" == "--help" ]]; then
    show_usage
    exit 0
  elif [[ "$mode" != "light" ]] && [[ "$mode" != "dark" ]]; then
    echo "Mode must be 'light' or 'dark'." >&2
    exit 2
  fi

  tmux_set_theme_mode "$mode"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
  case "${1-}" in
  --daemon)
    daemon_mode
    ;;
  --theme)
    theme_mode "${2-}"
    ;;
  --help | -h)
    show_usage
    exit 0
    ;;
  "")
    entry_point_mode
    ;;
  *)
    echo "Unknown option: $1" >&2
    show_usage
    exit 1
    ;;
  esac
}

main "$@"
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n main.tmux && echo "Syntax OK"
```

Expected: `Syntax OK`

---

### Task 5: Update README.md

Add Linux support documentation while keeping all existing macOS docs.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the title and description**

Change line 1 from:
```
# tmux-dark-notify - Make tmux's theme follow macOS dark/light mode
```
to:
```
# tmux-dark-notify - Make tmux's theme follow system dark/light mode
```

Change the intro paragraph from:
```
This tmux [tpm][t] plugin automatically changes the tmux theme when the system switches between light/dark mode. Configure light and dark themes, and the plugin handles the rest!
```
to:
```
This tmux [tpm][t] plugin automatically changes the tmux theme when the system switches between light/dark mode on **macOS** and **Linux** (GNOME, KDE Plasma, COSMIC). Configure light and dark themes, and the plugin handles the rest!
```

- [ ] **Step 2: Update the Features section**

Replace:
```
- 🌙 **Automatic theme switching** - Responds to macOS system appearance changes
- 🔒 **Robust process management** - Lock file system prevents duplicate instances
- 🎯 **Single-file design** - Simple unified script architecture
```
with:
```
- 🌙 **Automatic theme switching** - Responds to system appearance changes on macOS and Linux
- 🔒 **Robust process management** - Per-server PID tracking prevents duplicate instances
- 🎯 **Modular design** - Platform-specific backends with shared core
- 🐧 **Linux support** - GNOME, KDE Plasma, and COSMIC via freedesktop portal with DE-specific fallbacks
```

- [ ] **Step 3: Update the Requirements section**

Replace the entire Requirements section with:

```markdown
## Requirements

### macOS

- **Bash** - For script execution
- **Homebrew** - Package manager for dependencies
- **[dark-notify][dn]** - Install with `brew install cormacrelf/tap/dark-notify`
- **tmux** - Terminal multiplexer
- **[tpm][t]** - Tmux Plugin Manager (optional but recommended)

### Linux

- **Bash** - For script execution
- **tmux** - Terminal multiplexer
- **[tpm][t]** - Tmux Plugin Manager (optional but recommended)
- **One of the following desktop environments:**
  - **GNOME** - Uses `gsettings` or freedesktop portal (both typically pre-installed)
  - **KDE Plasma** - Uses freedesktop portal via `dbus-send` and `dbus-monitor`
  - **COSMIC (Pop!_OS)** - Reads config files directly; optionally install `inotify-tools` for instant detection
```

- [ ] **Step 4: Add Linux installation instructions**

After the existing macOS installation step 1, add a Linux alternative:

```markdown
1. **Install dependencies:**

   **macOS:**
   ```bash
   brew install cormacrelf/tap/dark-notify
   ```

   **Linux (GNOME/KDE):** No additional dependencies — `dbus` and `gsettings` are typically pre-installed.

   **Linux (COSMIC):** Optionally install `inotify-tools` for instant theme detection:
   ```bash
   # Debian/Ubuntu/Pop!_OS
   sudo apt install inotify-tools

   # Fedora
   sudo dnf install inotify-tools

   # Arch
   sudo pacman -S inotify-tools
   ```
```

- [ ] **Step 5: Update Troubleshooting section**

After the existing "Plugin Not Working" subsection, add:

```markdown
### Linux: No Detection Method Found

The plugin auto-detects your desktop environment. If it can't find a supported method:

1. **Check freedesktop portal:**
   ```bash
   dbus-send --session --print-reply \
     --dest=org.freedesktop.portal.Desktop \
     /org/freedesktop/portal/desktop \
     org.freedesktop.portal.Settings.Read \
     string:'org.freedesktop.appearance' string:'color-scheme'
   ```

2. **Check GNOME gsettings:**
   ```bash
   gsettings get org.gnome.desktop.interface color-scheme
   ```

3. **Check COSMIC config:**
   ```bash
   cat ~/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark
   ```
```

- [ ] **Step 6: Update the lock file references in Troubleshooting**

In the "Multiple Instances Running" section, replace:

```markdown
The plugin uses a lock file system to prevent duplicate instances. If you see issues:

1. **Remove stale lock file:**
   ```bash
   rm ~/.local/state/tmux/tmux-dark-notify.lock
   ```
```

with:

```markdown
The plugin uses per-server PID files to prevent duplicate instances. If you see issues:

1. **Remove stale PID files:**
   ```bash
   rm ~/.local/state/tmux/tmux-dark-notify-*.pid
   ```
```

---

### Task 6: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite CLAUDE.md to reflect new architecture**

Replace full contents with:

```markdown
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
```

---

### Task 7: Verify all syntax and commit

**Files:**
- All modified/created files

- [ ] **Step 1: Verify syntax of all bash scripts**

```bash
bash -n main.tmux && echo "main.tmux OK"
bash -n scripts/backend-macos.sh && echo "backend-macos.sh OK"
bash -n scripts/backend-linux.sh && echo "backend-linux.sh OK"
```

Expected: All three print OK (backend-linux.sh may print OK even without dbus-send since `bash -n` only parses, doesn't execute).

- [ ] **Step 2: Verify file permissions**

```bash
ls -la main.tmux scripts/backend-*.sh
```

Expected: All files have execute permission.

- [ ] **Step 3: Stage and commit all changes**

```bash
git add main.tmux scripts/backend-macos.sh scripts/backend-linux.sh \
  README.md CLAUDE.md \
  docs/superpowers/specs/2026-04-07-linux-desktop-support-design.md \
  docs/superpowers/plans/2026-04-07-linux-desktop-support.md
git commit -m "feat: add Linux desktop environment support (GNOME, KDE, COSMIC)

Add platform-specific backends for macOS and Linux with a freedesktop
portal → GNOME → KDE → COSMIC fallback chain. Adopt per-server PID
tracking and improved signal handling from upstream.

- Extract macOS logic to scripts/backend-macos.sh
- Create scripts/backend-linux.sh with DE detection
- Refactor main.tmux for platform dispatch
- Replace single lock file with per-server PID files
- Update README.md with Linux documentation
- Update CLAUDE.md with new architecture"
```
