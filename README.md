<p align="center" dir="auto">
  <img src="resources/header-image.png" alt="Barik">
  <p align="center" dir="auto">
    <a href="LICENSE">
      <img alt="License Badge" src="https://img.shields.io/github/license/ojowwalker77/barik.svg?color=green" style="max-width: 100%;">
    </a>
    <a href="https://github.com/ojowwalker77/barik/issues">
      <img alt="Issues Badge" src="https://img.shields.io/github/issues/ojowwalker77/barik.svg?color=green" style="max-width: 100%;">
    </a>
    <a href="CHANGELOG.md">
      <img alt="Changelog Badge" src="https://img.shields.io/badge/view-changelog-green.svg" style="max-width: 100%;">
    </a>
    <a href="https://github.com/ojowwalker77/barik/releases">
      <img alt="GitHub Downloads (all assets, all releases)" src="https://img.shields.io/github/downloads/ojowwalker77/barik/total">
    </a>
  </p>
</p>

**barik** is a lightweight macOS menu bar replacement. If you use [**yabai**](https://github.com/koekeishiya/yabai) or [**AeroSpace**](https://github.com/nikitabobko/AeroSpace) for tiling WM, you can display the current space in a sleek macOS-style panel with smooth animations. This makes it easy to see which number to press to switch spaces.

<br>

<div align="center">
  <h3>Screenshots</h3>
  <img src="resources/preview-image-light.png" alt="Barik Light Theme">
  <img src="resources/preview-image-dark.png" alt="Barik Dark Theme">
</div>
<br>
<div align="center">
  <h3>Video</h3>
  <video src="https://github.com/user-attachments/assets/33cfd2c2-e961-4d04-8012-664db0113d4f">
</div>

https://github.com/user-attachments/assets/d3799e24-c077-4c6a-a7da-a1f2eee1a07f

<br>

## Credits

This is a fork of [**barik**](https://github.com/mocki-toki/barik) by [**mocki-toki**](https://github.com/mocki-toki). Thank you for creating this project!

<br>

## Requirements

- macOS 15.0+

## Installation

### Homebrew (recommended)

```bash
brew tap ojowwalker77/barik
brew install --cask barik
```

To update:
```bash
brew upgrade barik
```

### Manual

Download from [Releases](https://github.com/ojowwalker77/barik/releases), unzip, and move to Applications.

### Setup

1. _(Optional)_ Install [**yabai**](https://github.com/koekeishiya/yabai) or [**AeroSpace**](https://github.com/nikitabobko/AeroSpace) for workspace support. Configure top padding — [yabai example](https://github.com/ojowwalker77/barik/blob/main/example/.yabairc).

2. Hide the system menu bar: **System Settings → Control Center → Automatically hide and show the menu bar → Always**

3. Uncheck **Desktop & Dock → Show items → On Desktop**

4. Launch **barik** and add to login items.

<br>

## Configuration

Config file: `~/.config/barik/config.toml` or `~/.barik-config.toml`

```toml
theme = "system" # system, light, dark

[widgets]
displayed = [
    "default.spaces",
    "spacer",
    "default.network",
    "default.battery",
    "default.bluetooth",
    "divider",
    "default.time"
]

[background]
enabled = true

[experimental.foreground]
position = "top" # top, bottom
horizontal-padding = 25
```

### Widgets

| Widget | ID |
|--------|-----|
| Spaces | `default.spaces` |
| Time | `default.time` |
| Battery | `default.battery` |
| Network | `default.network` |
| Bluetooth | `default.bluetooth` |
| Now Playing | `default.nowplaying` |
| Divider | `divider` |
| Flexible Space | `spacer` |

### Custom Paths

```toml
[yabai]
path = "/path/to/yabai"

[aerospace]
path = "/path/to/aerospace"
```

<br>

## Customization

Click the **gear icon** to customize your toolbar:

- Drag widgets to add/remove/reorder
- Widgets are organized into left, center, and right zones
- Center zone stays screen-centered

<br>

## Now Playing

Supports any media app through MediaRemote framework. Tested with:
- Spotify
- Apple Music
- Browser media

<br>

## FAQ

**Where are menu items (File, Edit, etc.)?**

Not supported yet. Use [Raycast](https://www.raycast.com/) or move mouse to top to reveal system menu bar.

<br>

## Contributing

PRs welcome!

## License

[MIT](LICENSE)
