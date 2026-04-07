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
  local -a callback=("$@")
  dbus-monitor --session \
    "type='signal',interface='org.freedesktop.portal.Settings',member='SettingChanged',arg0='org.freedesktop.appearance',arg1='color-scheme'" 2>/dev/null |
  while read -r line; do
    if [[ "$line" == *"uint32"* ]]; then
      local value
      value=$(echo "$line" | grep -o 'uint32 [0-9]*' | tail -1 | cut -d' ' -f2)
      if [[ "$value" == "1" ]]; then
        "${callback[@]}" dark
      else
        "${callback[@]}" light
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
  local -a callback=("$@")
  gsettings monitor org.gnome.desktop.interface color-scheme 2>/dev/null |
  while read -r _key value; do
    if [[ "$value" == *"prefer-dark"* ]]; then
      "${callback[@]}" dark
    else
      "${callback[@]}" light
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
      if [[ "$scheme" == *[Dd]ark* ]]; then
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
  local -a callback=("$@")
  dbus-monitor --session \
    "type='signal',interface='org.freedesktop.portal.Settings',member='SettingChanged',arg0='org.freedesktop.appearance',arg1='color-scheme'" 2>/dev/null |
  while read -r line; do
    if [[ "$line" == *"uint32"* ]]; then
      local value
      value=$(echo "$line" | grep -o 'uint32 [0-9]*' | tail -1 | cut -d' ' -f2)
      if [[ "$value" == "1" ]]; then
        "${callback[@]}" dark
      else
        "${callback[@]}" light
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
  local -a callback=("$@")
  if command -v inotifywait &>/dev/null; then
    inotifywait -m -e modify "$_COSMIC_CONFIG" 2>/dev/null |
    while read -r _dir _events _file; do
      local mode
      mode=$(_cosmic_detect_mode)
      "${callback[@]}" "$mode"
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
        "${callback[@]}" "$current_mode"
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

  # 3. Try KDE (check that KDE is actually the running desktop)
  if [[ "${XDG_CURRENT_DESKTOP-}" == *"KDE"* ]] && command -v dbus-send &>/dev/null; then
    LINUX_BACKEND="kde"
    return
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
  case "$LINUX_BACKEND" in
    portal) _portal_monitor_changes "$@" ;;
    gnome)  _gnome_monitor_changes "$@" ;;
    kde)    _kde_monitor_changes "$@" ;;
    cosmic) _cosmic_monitor_changes "$@" ;;
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
