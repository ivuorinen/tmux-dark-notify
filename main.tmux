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

  # Atomic PID file creation via noclobber
  if ! (set -C; echo $$ > "$pid_file") 2>/dev/null; then
    return 1
  fi
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

  # Expand $HOME and ~ in theme path (safe alternative to eval)
  theme_path="${theme_path//\$HOME/$HOME}"
  theme_path="${theme_path/#\~/$HOME}"
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
  # Kill the monitor process group to terminate all children
  [[ -n "${MONITOR_PID-}" ]] && { kill -TERM -"$MONITOR_PID" 2>/dev/null || true; }
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

  # Set initial theme before monitoring for changes
  local initial_mode
  initial_mode=$(backend_detect_mode)
  tmux_set_theme_mode "$initial_mode"

  while :; do
    # Start backend_monitor_changes in its own process group using setsid
    # so that cleanup() can kill the entire process group
    # Source the backend script in the subshell so it can access backend_monitor_changes
    setsid bash -c '
      case "$OSTYPE" in
        darwin*) source "'"$SCRIPT_DIR"'/scripts/backend-macos.sh" ;;
        linux*)  source "'"$SCRIPT_DIR"'/scripts/backend-linux.sh" ;;
      esac
      exec backend_monitor_changes "$@"
    ' _ "$0" "--theme" &
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