#!/usr/bin/env bash
# tmux-dark-notify - Make tmux's theme follow macOS dark/light mode
#
# This unified script handles all functionality:
# - Entry point: Launch daemon if not running
# - Daemon mode: Run dark-notify loop
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

# Lock file management
TMUX_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
LOCK_FILE="${TMUX_STATE_DIR}/tmux-dark-notify.lock"

# Theme configuration
OPTION_THEME_LIGHT="@dark-notify-theme-path-light"
OPTION_THEME_DARK="@dark-notify-theme-path-dark"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

program_is_in_path() {
  type "$1" >/dev/null 2>&1
}

is_process_running() {
  local pid=$1
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# =============================================================================
# LOCK FILE MANAGEMENT
# =============================================================================

create_lock() {
  # Ensure state directory exists
  if [[ ! -d "$TMUX_STATE_DIR" ]]; then
    if ! mkdir -p "$TMUX_STATE_DIR"; then
      echo "Failed to create tmux state directory: $TMUX_STATE_DIR" >&2
      return 1
    fi
  fi

  # Atomic lock file creation
  if (
    set -C
    {
      echo "PID: $$"
      echo "STARTED: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "HOSTNAME: $(hostname)"
      echo "SCRIPT: $SCRIPT_NAME"
    } >"$LOCK_FILE"
  ) 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

check_lock() {
  [[ -f "$LOCK_FILE" ]] || return 1

  local lock_pid
  lock_pid=$(grep "^PID:" "$LOCK_FILE" 2>/dev/null | cut -d' ' -f2)

  if [[ -z "$lock_pid" ]]; then
    # Malformed lock file
    return 1
  fi

  if is_process_running "$lock_pid"; then
    # Process is running, lock is valid
    return 0
  else
    # Stale lock, remove it
    remove_lock
    return 1
  fi
}

remove_lock() {
  [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
}

cleanup_and_exit() {
  remove_lock
  exit 0
}

is_runner_active() {
  check_lock
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

  # Ensure state directory exists
  if [[ ! -d "$TMUX_STATE_DIR" ]]; then
    if ! mkdir -p "$TMUX_STATE_DIR"; then
      echo "Failed to create tmux state directory: $TMUX_STATE_DIR" >&2
      exit 3
    fi
  fi

  local theme_path
  if [[ "$mode" = "dark" ]]; then
    theme_path=$(tmux_get_option "$OPTION_THEME_DARK")
  else
    theme_path=$(tmux_get_option "$OPTION_THEME_LIGHT")
  fi

  # Expand e.g. $HOME
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
tmux-dark-notify - Make tmux's theme follow macOS dark/light mode

Usage:
  $SCRIPT_NAME                 Launch daemon (default mode)
  $SCRIPT_NAME --daemon        Run dark-notify daemon loop
  $SCRIPT_NAME --theme <mode>  Set theme (light|dark)
  $SCRIPT_NAME --help          Show this help

Examples:
  $SCRIPT_NAME --theme dark    Set dark theme
  $SCRIPT_NAME --theme light   Set light theme
EOF
}

entry_point_mode() {
  # Check if runner is already active
  if is_runner_active; then
    # Already running, nothing to do
    exit 0
  fi

  # Launch daemon in background with proper detachment
  # Redirect stdin/stdout/stderr to prevent tmux hanging
  nohup "$0" --daemon </dev/null >/dev/null 2>&1 &

  # Give the daemon a moment to start and create lock file
  sleep 0.1
}

daemon_mode() {
  if check_lock; then
    # When refreshing tmux config the message is shown.
    # This checks if we are in a tmux session, and doesn't echo it.
    if [[ ! "$TMUX" ]]; then
      echo "$SCRIPT_NAME daemon is already running, nothing to do here."
    fi
    exit 0
  fi

  # Try to create lock file
  if ! create_lock; then
    if [[ ! "$TMUX" ]]; then
      echo "Failed to create lock file. Another instance may be starting." >&2
    fi
    exit 1
  fi

  # Set up signal handlers for cleanup
  trap cleanup_and_exit SIGTERM SIGINT SIGHUP

  # If BREW_PREFIX is already set, skip calling brew shellenv
  if [[ -z "${BREW_PREFIX-}" ]]; then
    # Load Homebrew PATHs
    if ! program_is_in_path brew; then
      echo "Could not find brew(1) in \$PATH" >&2
      exit 1
    fi
    eval "$(brew shellenv)"
  fi

  if ! program_is_in_path dark-notify; then
    echo "Could not find dark-notify(1) in \$PATH" >&2
    exit 1
  fi

  while :; do
    dark-notify -c "$0 --theme"
    sleep 1 # Throttle the loop
  done

  # This should never be reached, but clean up just in case
  cleanup_and_exit
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
    # Default mode: entry point
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
