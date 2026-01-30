# Barik Premium Roadmap

## Phase 1: Polish & Feedback

### Haptic Feedback
- [ ] Add haptic feedback on every interaction:
  - Widget added to toolbar
  - Widget removed from toolbar
  - Widget reordered
  - Drop successful
  - Settings saved
  - Button presses in settings

### Elastic Drag Physics
- [ ] Widgets stretch slightly when dragged (elastic effect)
- [ ] Spring physics for snap-back when drop rejected
- [ ] Subtle scale-up when hovering over drop targets
- [ ] Smooth interpolation for insertion indicators

### Pin Documents/Folders
- [ ] Drag file/folder from Finder to bar
- [ ] Creates a pin widget showing file name + icon
- [ ] Clicking opens the file/folder
- [ ] Right-click to unpin
- [ ] Visual feedback during drag (highlight drop zone)
- [ ] Store pinned items in config

---

## Phase 2: New Widgets

### System Stats Widget
- [ ] Mini CPU usage graph (sparkline)
- [ ] Mini Memory usage graph
- [ ] Click for detailed popup with full stats
- [ ] **Performance requirements:**
  - Sample every 2-3 seconds max (not aggressive polling)
  - Use lightweight system APIs (host_statistics, mach_task_basic_info)
  - Lazy initialization - only active when widget visible
  - Pause updates when menu closed
  - Efficient Core Animation layers for graph rendering
  - Memory-mapped ring buffer for history (keep last 60 points)

---

## Phase 3: Architecture Improvements

### Grid-Based Positioning System (High Priority)
Transform the bar from free-form positioning to a grid system like Safari:

**Grid System Design:**
- [ ] Define grid cell size (e.g., 40px width slots)
- [ ] Calculate each widget's width in grid units (1x, 2x, 3x slots)
- [ ] Widgets declare their grid footprint (compact=1, normal=2, wide=3)
- [ ] Track occupied grid slots in the bar
- [ ] Dragging snaps to nearest available grid slot
- [ ] Visual grid lines during customization mode (faint)
- [ ] Widgets can only be placed where they fit

**Benefits:**
- Predictable positioning (no overlapping)
- Consistent spacing automatically
- Easier drag-and-drop (clear snap targets)
- Supports variable-width widgets cleanly
- Future: custom widget sizes (user resizable)

**Implementation:**
- [ ] Add `gridWidth: Int` property to each widget definition
- [ ] Grid manager tracks slot occupancy
- [ ] Convert x-coordinates to/from grid positions
- [ ] Snap animation when dropping
- [ ] Show grid overlay faintly during customization

### Widget Protocol System
- [ ] Define `BarikWidget` protocol for easier plugin creation:
  ```swift
  protocol BarikWidget {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var content: AnyView { get }
    var popupContent: AnyView? { get }
  }
  ```
- [ ] Widget registry with automatic discovery
- [ ] Declarative widget configuration
- [ ] Support for third-party widget plugins

### Unified Animation System
- [ ] Centralized animation configuration
- [ ] Consistent spring physics across all interactions
- [ ] Animation presets: .widgetAdd, .widgetRemove, .reorder, .hover
- [ ] Disable animations for accessibility (respect reduce motion)

### Better State Management
- [ ] Single source of truth for widget layout
- [ ] Eliminate duplication between customization and normal modes
- [ ] Reactive config updates without manual notification posting
- [ ] Proper SwiftUI state binding between view model and views
- [ ] Undo/redo system for all customization actions

---

## Phase 4: Visual Polish (Post-MVP)

- [ ] Frosted glass backdrop blur behind widgets
- [ ] Subtle inner shadows on widget containers
- [ ] Animated gradient borders during customization mode
- [ ] Depth effects (widgets lift on hover with shadow)
- [ ] Smooth color transitions for theme changes
- [ ] Custom accent color support
- [ ] Widget hover states with glow effects
- [ ] Customizable widget spacing per-widget

---

## Completed

- [x] Fix position picker (added to Safari-style Customize Toolbar sheet)
- [x] Lock settings widget to right side (always visible, not removable)
- [x] Fix spacer/divider rendering in customization mode
- [x] Fix drag-out-to-remove functionality
- [x] Ensure Done button triggers proper config reload
- [x] Remove old tabbed SettingsPopup - now only Safari-style toolbar customization
