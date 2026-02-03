# Changelog

## 0.6.2-rc

### Popups
- Auto-size popups to content with live resizing and better screen clamping
- Align popup content to the bar edge for more accurate anchoring
- Debug logging only in debug builds

### Battery
- Battery icon turns yellow in Low Power Mode and red at warning level
- Battery popup color now mirrors the widget state
- Power source updates use notifications with a low-frequency fallback timer

### Bluetooth
- Bluetooth popup lists available Bluetooth output devices
- Switch audio output devices directly from the popup

### Settings
- Show the canonical config file path (with copy action) in customization
- Auto-save customization changes when the app quits

## 0.6.1

### Multi-Monitor Support
- Bar displays on all connected monitors
- Each monitor shows only its own workspaces (AeroSpace/yabai)
- Auto-configures tiling WM gaps per-monitor

### Zone-Based Layout
- Widgets organized into left, center, and right zones
- Center zone stays perfectly screen-centered
- Safari-style drag-and-drop customization
- Zone capacity indicators in settings

### New Widget
- **Bluetooth widget** — shows connected audio output device

### Now Playing Improvements
- MediaRemote adapter for universal media detection
- Works with any media app, not just Apple Music/Spotify
- Notification-based updates instead of polling
- Widget hides when paused

### Bar Positioning
- Switch between top and bottom positioning
- Auto-hide macOS menu bar when bar is at top
- AppleScript-based menu bar toggling

### Fixes & Improvements
- Reduced console spam (spaces polling 10Hz → 1Hz)
- Fixed JSON decode errors for non-JSON aerospace responses
- Fixed calendar event fetching when access denied
- App name caching to reduce filesystem I/O
- CalendarManager singleton to prevent duplicate instances

---

## 0.5.1

> This release was supported by **ALinuxPerson**, **bake**, and **Oery**

- Added yabai.path and aerospace.path config properties
- Fixed popup design
- Fixed Apple Music integration in Now Playing widget
- Added experimental appearance configuration

## 0.5.0

- Added **Now Playing** widget for Apple Music and Spotify
- Added **Popup** feature for interactive widget views
- Space key and title visibility options
- Click to switch windows and spaces
- Auto update functionality

## 0.4.1

- Fixed display issue with Notch

## 0.4.0

- Added `~/.barik-config.toml` configuration
- Added AeroSpace support
- Fixed 24-hour time format
- Fixed desktop icon display

## 0.3.0

- Added network widget
- Added power plug battery status
- Max length for window titles

## 0.2.0

- Light theme support

## 0.1.0

- Initial release
