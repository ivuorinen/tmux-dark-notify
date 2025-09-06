# tmux-dark-notify - Make tmux's theme follow macOS dark/light mode

This tmux [tpm][t] plugin automatically changes the tmux theme when the system switches between light/dark mode. Configure light and dark themes, and the plugin handles the rest!


![Demo of changing system theme](demo.gif)

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Tips & Related Tools](#tips--related-tools)
- [More tmux plugins](#more-tmux-plugins)

## Features

- 🌙 **Automatic theme switching** - Responds to macOS system appearance changes
- 🔒 **Robust process management** - Lock file system prevents duplicate instances
- 🎯 **Single-file design** - Simple unified script architecture
- 🛠️ **Manual control** - Switch themes manually when needed
- 📁 **State management** - Maintains theme symlinks for tmux config integration
- 🔧 **Error handling** - Comprehensive validation and helpful error messages

## Requirements

- **macOS** - dark-notify is macOS-specific
- **Bash** - For script execution
- **Homebrew** - Package manager for dependencies
- **[dark-notify][dn]** - Install with `brew install dark-notify`
- **tmux** - Terminal multiplexer
- **[tpm][t]** - Tmux Plugin Manager (optional but recommended)

## Installation

1. **Install dependencies:**
   ```bash
   brew install dark-notify
   ```

2. **Add plugin to tmux.conf:**
   ```conf
   set -g @plugin 'ivuorinen/tmux-dark-notify'
   ```

3. **Install with tpm:**
   Press `<prefix>I` (default: `Ctrl-b I`) to install the plugin.

## Configuration

### 1. Configure Theme Paths

Add these options to your `tmux.conf` before the tpm initialization:

```conf
set -g @dark-notify-theme-path-light '/path/to/your/light-theme.conf'
set -g @dark-notify-theme-path-dark '/path/to/your/dark-theme.conf'
```

**Example with Solarized themes:**
```conf
set -g @dark-notify-theme-path-light '$HOME/.config/tmux/plugins/tmux-colors-solarized/tmuxcolors-light.conf'
set -g @dark-notify-theme-path-dark '$HOME/.config/tmux/plugins/tmux-colors-solarized/tmuxcolors-dark.conf'
```

### 2. Add Theme Fallback (Recommended)

Add this **after** tpm initialization to ensure themes load even if the plugin hasn't run yet:

```conf
# Initialize tpm (this line should already exist)
run '~/.config/tmux/plugins/tpm/tpm'

# Fallback theme loading
if-shell "test -e ~/.local/state/tmux/tmux-dark-notify-theme.conf" \
  "source-file ~/.local/state/tmux/tmux-dark-notify-theme.conf"
```

### 3. Complete Configuration Example

```conf
# Theme plugins (install these first)
set -g @plugin 'seebi/tmux-colors-solarized'
set -g @plugin 'ivuorinen/tmux-dark-notify'

# Configure theme paths
set -g @dark-notify-theme-path-light '$HOME/.config/tmux/plugins/tmux-colors-solarized/tmuxcolors-light.conf'
set -g @dark-notify-theme-path-dark '$HOME/.config/tmux/plugins/tmux-colors-solarized/tmuxcolors-dark.conf'

# Initialize tpm
run '~/.config/tmux/plugins/tpm/tpm'

# Fallback theme loading
if-shell "test -e ~/.local/state/tmux/tmux-dark-notify-theme.conf" \
  "source-file ~/.local/state/tmux/tmux-dark-notify-theme.conf"
```

### 4. Verify Installation

1. Reload tmux config: `<prefix>r` or restart tmux
2. Check the theme symlink:
   ```bash
   ls -l ~/.local/state/tmux/tmux-dark-notify-theme.conf
   ```
3. Toggle your system appearance mode and watch tmux theme change!

## Usage

The plugin runs automatically once installed, but you can also use it manually:

### Automatic Mode (Default)

The plugin launches automatically with tmux and runs in the background, monitoring for system appearance changes.

### Manual Theme Switching

```bash
# Switch to dark theme
~/.config/tmux/plugins/tmux-dark-notify/main.tmux --theme dark

# Switch to light theme
~/.config/tmux/plugins/tmux-dark-notify/main.tmux --theme light
```

### Daemon Control

```bash
# Start daemon manually
~/.config/tmux/plugins/tmux-dark-notify/main.tmux --daemon

# Show help
~/.config/tmux/plugins/tmux-dark-notify/main.tmux --help
```

## Troubleshooting

### Plugin Not Working

1. **Check dark-notify installation:**
   ```bash
   which dark-notify
   # Should output: /opt/homebrew/bin/dark-notify (or similar)
   ```

2. **Verify theme paths exist:**

   ```bash
   # Check if your theme files are readable
   test -r "$HOME/.config/tmux/plugins/tmux-colors-solarized/tmuxcolors-light.conf" && echo "Light theme OK"
   test -r "$HOME/.config/tmux/plugins/tmux-colors-solarized/tmuxcolors-dark.conf" && echo "Dark theme OK"
   ```

3. **Check plugin status:**
   ```bash
   # Look for running daemon
   ps aux | grep tmux-dark-notify

   # Check lock file
   ls -la ~/.local/state/tmux/tmux-dark-notify.lock
   ```

### Themes Not Switching

1. **Verify tmux options are set:**
   ```bash
   tmux show-options -g | grep dark-notify
   ```
2. **Test manual switching:**
   ```bash
   ~/.config/tmux/plugins/tmux-dark-notify/main.tmux --theme dark
   ```
3. **Check theme symlink:**
   ```bash
   ls -l ~/.local/state/tmux/tmux-dark-notify-theme.conf
   ```

### Multiple Instances Running

The plugin uses a lock file system to prevent duplicate instances. If you see issues:

1. **Remove stale lock file:**
   ```bash
   rm ~/.local/state/tmux/tmux-dark-notify.lock
   ```

2. **Restart the plugin:**
   ```bash
   ~/.config/tmux/plugins/tmux-dark-notify/main.tmux
   ```

## Advanced Usage

### Custom State Directory

Set a custom state directory using the XDG specification:

```bash
export XDG_STATE_HOME="$HOME/.local/state"
```

### Debug Mode

Enable trace mode for debugging:

```bash
TRACE=1 ~/.config/tmux/plugins/tmux-dark-notify/main.tmux --daemon
```

### Integration with Scripts

You can call the theme switcher from your own scripts:

```bash
#!/bin/bash
# Switch to dark theme for late-night coding
~/.config/tmux/plugins/tmux-dark-notify/main.tmux --theme dark
```

## Tips & Related Tools

### NeoVim Integration

Set up [dark-notify][dn] to change your Neovim theme as well!

### iTerm2 Auto-Switching

Use iTerm2 version ≥3.5 for automatic terminal theme switching:
1. Go to **iTerm2 Preferences → Profiles → [your profile] → Colors**
2. Check **"Use different colors for light and dark mode"**
3. Configure your light and dark color schemes

### Global Keyboard Shortcut

Create a macOS keyboard shortcut to toggle system appearance:

1. **Create Quick Action in Automator:**
   - Open Automator.app
   - Create a new **Quick Action**
   - Add **"Change System Appearance"** action
   - Set to **"Toggle Light/Dark"**
   - Save as `appearance_toggle`
2. **Add Keyboard Shortcut:**
   - Open **System Settings → Keyboard → Keyboard Shortcuts → Services**
   - Find your `appearance_toggle` service under **General**
   - Assign a shortcut (e.g., **⌃⌥⌘T**)

---

Built on top of the excellent [dark-notify][dn] by Cormac Relf and original [tmux-dark-notify][orig] by [Erik Westrup][e]!*

[dn]: https://github.com/cormacrelf/dark-notify
[t]: https://github.com/tmux-plugins/tpm
[orig]: https://github.com/erikw/tmux-dark-notify
[e]: https://github.com/erikw
