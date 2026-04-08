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

# Blocks and calls <callback...> with "dark" or "light" on appearance change.
# Usage: backend_monitor_changes "/path/to/script" "--theme"
backend_monitor_changes() {
  local cmd
  # dark-notify -c expects a shell command string; reconstruct safely from argv
  printf -v cmd '%q ' "$@"
  dark-notify -c "${cmd% }"
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
