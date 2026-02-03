import Foundation
import SwiftUI

/// Single placement = widget + zone + position within zone
struct WidgetPlacement: Identifiable, Equatable {
    let id: UUID
    let widgetId: String
    var zone: Zone
    var orderInZone: Int
    var compactionLevel: CompactionLevel

    var width: Int {
        let definition = WidgetRegistry.widget(for: widgetId)
        let sizes = definition?.sizes ?? WidgetSizeSpec(full: 2)
        return sizes.columns(for: compactionLevel) ?? sizes.full
    }

    init(
        id: UUID = UUID(),
        widgetId: String,
        zone: Zone,
        orderInZone: Int = 0,
        compactionLevel: CompactionLevel = .full
    ) {
        self.id = id
        self.widgetId = widgetId
        self.zone = zone
        self.orderInZone = orderInZone
        self.compactionLevel = compactionLevel
    }
}

/// Layout engine using zone-based positioning for widgets
@Observable
final class WidgetGridEngine {
    static let shared = WidgetGridEngine()

    // MARK: - Configuration

    let totalCells: Int = 20
    let compactionThreshold: Double = 0.85

    // MARK: - State

    private(set) var leftPlacements: [WidgetPlacement] = []
    private(set) var centerPlacements: [WidgetPlacement] = []
    private(set) var rightPlacements: [WidgetPlacement] = []

    /// Compaction states per widget instance
    private(set) var compactionStates: [UUID: CompactionLevel] = [:]

    /// Widgets that are in the overflow menu (hidden due to space)
    private(set) var overflowWidgets: [WidgetPlacement] = []

    var isCustomizing: Bool = false
    var hasUnsavedChanges: Bool = false

    /// Currently dragged placement (nil if dragging from palette)
    var draggedPlacementId: UUID?

    /// Widget ID being dragged (for palette drags)
    var draggedWidgetId: String?

    /// Target zone for drop
    var dropTargetZone: Zone?

    /// Target index within zone for drop
    var dropTargetIndex: Int?

    /// Whether currently dragging outside the bar (for removal)
    var isDraggingOutside: Bool = false

    // MARK: - Undo

    private var undoStack: [LayoutSnapshot] = []
    private var originalSnapshot: LayoutSnapshot?

    struct LayoutSnapshot: Equatable {
        let left: [WidgetPlacement]
        let center: [WidgetPlacement]
        let right: [WidgetPlacement]
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    // MARK: - Container Geometry

    var containerFrame: CGRect = .zero
    var horizontalPadding: CGFloat = 8
    var barHeight: CGFloat = 32

    /// Width of a single cell
    var cellWidth: CGFloat {
        guard containerFrame.width > 0 else { return 40 }
        return (containerFrame.width - horizontalPadding * 2) / CGFloat(totalCells)
    }

    // MARK: - Initialization

    private init() {
        // Load initial layout from config
        loadFromConfig()
    }

    // MARK: - Computed Properties

    /// All placements across all zones
    var allPlacements: [WidgetPlacement] {
        leftPlacements + centerPlacements + rightPlacements
    }

    /// Get placements for a specific zone
    func placements(for zone: Zone) -> [WidgetPlacement] {
        switch zone {
        case .left: return leftPlacements
        case .center: return centerPlacements
        case .right: return rightPlacements
        }
    }

    /// The dragged placement (if any)
    var draggedPlacement: WidgetPlacement? {
        guard let id = draggedPlacementId else { return nil }
        return allPlacements.first { $0.id == id }
    }

    /// Width of widget being dragged
    var draggedWidth: Int {
        if let placement = draggedPlacement {
            return placement.width
        }
        if let widgetId = draggedWidgetId {
            return WidgetRegistry.widget(for: widgetId)?.gridWidth ?? 2
        }
        return 2
    }

    // MARK: - Legacy Compatibility

    /// For backwards compatibility with existing code that uses flat placements array
    var placements: [WidgetPlacement] {
        allPlacements
    }

    /// Legacy cell-based positioning - now calculates based on zone positions
    var dropTargetCell: Int? {
        guard let zone = dropTargetZone, let index = dropTargetIndex else { return nil }
        let zonePlacements = placements(for: zone)

        var cell = zoneStartCell(for: zone)
        for (i, placement) in zonePlacements.enumerated() {
            if i == index { break }
            cell += placement.width
        }
        return cell
    }

    /// Calculate starting cell for a zone
    private func zoneStartCell(for zone: Zone) -> Int {
        switch zone {
        case .left:
            return 0
        case .center:
            let leftWidth = leftPlacements.reduce(0) { $0 + $1.width }
            let centerWidth = centerPlacements.reduce(0) { $0 + $1.width }
            let rightWidth = rightPlacements.reduce(0) { $0 + $1.width }
            // Center zone starts at middle minus half its width
            let totalUsed = leftWidth + centerWidth + rightWidth
            let availableGap = totalCells - totalUsed
            return leftWidth + availableGap / 2
        case .right:
            let rightWidth = rightPlacements.reduce(0) { $0 + $1.width }
            return totalCells - rightWidth
        }
    }

    // MARK: - Zone Calculations

    /// Calculate available cells for each zone
    func availableCells(for zone: Zone) -> Int {
        let used = placements(for: zone).reduce(0) { $0 + $1.width }
        let allocated = allocatedCells(for: zone)
        return max(0, allocated - used)
    }

    /// Calculate allocated cells for a zone based on content and layout rules
    private func allocatedCells(for zone: Zone) -> Int {
        let leftWidth = leftPlacements.reduce(0) { $0 + $1.width }
        let centerWidth = centerPlacements.reduce(0) { $0 + $1.width }
        let rightWidth = rightPlacements.reduce(0) { $0 + $1.width }

        // Center gets what it needs, left and right split the rest
        let centerAlloc = max(centerWidth, 4) // Minimum 4 cells for center
        let remaining = totalCells - centerAlloc

        switch zone {
        case .left:
            return remaining / 2
        case .center:
            return centerAlloc
        case .right:
            return remaining - remaining / 2
        }
    }

    /// Get the fill percentage for a zone (for capacity indicators)
    func fillPercentage(for zone: Zone) -> Double {
        let used = placements(for: zone).reduce(0) { $0 + $1.width }
        let allocated = allocatedCells(for: zone)
        guard allocated > 0 else { return 0 }
        return Double(used) / Double(allocated)
    }

    // MARK: - Compaction

    /// Run compaction algorithm for a zone
    func runCompaction(for zone: Zone) {
        let fillPct = fillPercentage(for: zone)
        guard fillPct > compactionThreshold else {
            // Reset compaction for zone
            for placement in placements(for: zone) {
                compactionStates[placement.id] = .full
            }
            return
        }

        // Sort by priority (lowest first - they get compacted first)
        var zonePlacements = placements(for: zone).sorted { p1, p2 in
            let pri1 = WidgetRegistry.widget(for: p1.widgetId)?.defaultPriority ?? 50
            let pri2 = WidgetRegistry.widget(for: p2.widgetId)?.defaultPriority ?? 50
            return pri1 < pri2
        }

        // Compact lowest priority widgets first
        var currentFill = fillPct
        for i in 0..<zonePlacements.count {
            guard currentFill > compactionThreshold else { break }

            let placement = zonePlacements[i]
            let definition = WidgetRegistry.widget(for: placement.widgetId)
            let sizes = definition?.sizes ?? WidgetSizeSpec(full: 2)

            let currentLevel = compactionStates[placement.id] ?? .full

            // Try to compact further
            if currentLevel == .full && sizes.compact != nil {
                compactionStates[placement.id] = .compact
                let saved = sizes.full - (sizes.compact ?? sizes.full)
                currentFill -= Double(saved) / Double(allocatedCells(for: zone))
            } else if currentLevel == .compact && sizes.iconOnly != nil {
                compactionStates[placement.id] = .iconOnly
                let saved = (sizes.compact ?? sizes.full) - (sizes.iconOnly ?? sizes.compact ?? sizes.full)
                currentFill -= Double(saved) / Double(allocatedCells(for: zone))
            } else if currentLevel != .hidden {
                // Move to overflow
                compactionStates[placement.id] = .hidden
                overflowWidgets.append(placement)
                zonePlacements[i].compactionLevel = .hidden
            }
        }
    }

    /// Run compaction for all zones
    func runCompactionAll() {
        overflowWidgets.removeAll()
        for zone in Zone.allCases {
            runCompaction(for: zone)
        }
    }

    // MARK: - Mutations

    private func recordState() {
        let snapshot = LayoutSnapshot(left: leftPlacements, center: centerPlacements, right: rightPlacements)
        undoStack.append(snapshot)
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }

    @discardableResult
    func insert(widgetId: String, in zone: Zone, at index: Int? = nil) -> WidgetPlacement? {
        recordState()

        let definition = WidgetRegistry.widget(for: widgetId)
        let insertIndex = index ?? placements(for: zone).count

        let placement = WidgetPlacement(
            id: UUID(),
            widgetId: widgetId,
            zone: zone,
            orderInZone: insertIndex
        )

        switch zone {
        case .left:
            leftPlacements.insert(placement, at: min(insertIndex, leftPlacements.count))
            reorderZone(&leftPlacements)
        case .center:
            centerPlacements.insert(placement, at: min(insertIndex, centerPlacements.count))
            reorderZone(&centerPlacements)
        case .right:
            rightPlacements.insert(placement, at: min(insertIndex, rightPlacements.count))
            reorderZone(&rightPlacements)
        }

        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        return placement
    }

    /// Legacy insert at cell position - maps to zone-based insert
    @discardableResult
    func insert(widgetId: String, at cell: Int) -> WidgetPlacement? {
        let zone = zoneForCell(cell)
        return insert(widgetId: widgetId, in: zone)
    }

    func move(id: UUID, to zone: Zone, at index: Int) {
        guard let placement = allPlacements.first(where: { $0.id == id }) else { return }
        recordState()

        // Remove from current zone
        removeFromZone(id: id)

        // Add to new zone
        var newPlacement = placement
        newPlacement.zone = zone
        newPlacement.orderInZone = index

        switch zone {
        case .left:
            leftPlacements.insert(newPlacement, at: min(index, leftPlacements.count))
            reorderZone(&leftPlacements)
        case .center:
            centerPlacements.insert(newPlacement, at: min(index, centerPlacements.count))
            reorderZone(&centerPlacements)
        case .right:
            rightPlacements.insert(newPlacement, at: min(index, rightPlacements.count))
            reorderZone(&rightPlacements)
        }

        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Legacy move to cell position - maps to zone-based move
    func move(id: UUID, to cell: Int) {
        let zone = zoneForCell(cell)
        let index = indexInZone(for: cell, zone: zone)
        move(id: id, to: zone, at: index)
    }

    func remove(id: UUID) {
        guard allPlacements.contains(where: { $0.id == id }) else { return }
        recordState()
        removeFromZone(id: id)
        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func removeFromZone(id: UUID) {
        leftPlacements.removeAll { $0.id == id }
        centerPlacements.removeAll { $0.id == id }
        rightPlacements.removeAll { $0.id == id }
        reorderZone(&leftPlacements)
        reorderZone(&centerPlacements)
        reorderZone(&rightPlacements)
    }

    private func reorderZone(_ placements: inout [WidgetPlacement]) {
        for i in 0..<placements.count {
            placements[i].orderInZone = i
        }
    }

    func resetToDefaults() {
        recordState()
        loadDefaultLayout()
        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        leftPlacements = previous.left
        centerPlacements = previous.center
        rightPlacements = previous.right
        hasUnsavedChanges = (originalSnapshot.map {
            leftPlacements != $0.left || centerPlacements != $0.center || rightPlacements != $0.right
        }) ?? true
    }

    // MARK: - Zone Helpers

    private func zoneForCell(_ cell: Int) -> Zone {
        let leftEnd = leftPlacements.reduce(0) { $0 + $1.width }
        let rightStart = totalCells - rightPlacements.reduce(0) { $0 + $1.width }

        if cell < leftEnd + 2 {
            return .left
        } else if cell >= rightStart - 2 {
            return .right
        } else {
            return .center
        }
    }

    private func indexInZone(for cell: Int, zone: Zone) -> Int {
        let zonePlacements = placements(for: zone)
        let zoneStart = zoneStartCell(for: zone)
        var currentCell = zoneStart

        for (index, placement) in zonePlacements.enumerated() {
            let midpoint = currentCell + placement.width / 2
            if cell < midpoint {
                return index
            }
            currentCell += placement.width
        }
        return zonePlacements.count
    }

    // MARK: - Customization Mode

    func startCustomizing() {
        loadFromConfig()
        undoStack.removeAll()
        originalSnapshot = LayoutSnapshot(left: leftPlacements, center: centerPlacements, right: rightPlacements)
        isCustomizing = true
        hasUnsavedChanges = false
    }

    func finishCustomizing() {
        if hasUnsavedChanges {
            saveToConfig()
        }
        isCustomizing = false
        clearDragState()
    }

    func cancelCustomizing() {
        if let original = originalSnapshot {
            leftPlacements = original.left
            centerPlacements = original.center
            rightPlacements = original.right
        }
        isCustomizing = false
        hasUnsavedChanges = false
        clearDragState()
    }

    // MARK: - Drag Operations

    func beginDragFromBar(placementId: UUID) {
        draggedPlacementId = placementId
        draggedWidgetId = nil
        isDraggingOutside = false
        dropTargetZone = nil
        dropTargetIndex = nil
    }

    func beginDragFromPalette(widgetId: String) {
        draggedPlacementId = nil
        draggedWidgetId = widgetId
        isDraggingOutside = false
        dropTargetZone = nil
        dropTargetIndex = nil
    }

    func updateDrag(location: CGPoint, isOutside: Bool) {
        isDraggingOutside = isOutside

        if isOutside {
            dropTargetZone = nil
            dropTargetIndex = nil
            return
        }

        // Determine zone from X position
        let relativeX = location.x - horizontalPadding
        let totalWidth = containerFrame.width - horizontalPadding * 2

        let zone: Zone
        if relativeX < totalWidth * 0.33 {
            zone = .left
        } else if relativeX > totalWidth * 0.67 {
            zone = .right
        } else {
            zone = .center
        }

        dropTargetZone = zone

        // Calculate index within zone
        let zonePlacements = placements(for: zone)
        let zoneWidth = totalWidth / 3
        let zoneStart: CGFloat
        switch zone {
        case .left: zoneStart = 0
        case .center: zoneStart = totalWidth / 3
        case .right: zoneStart = totalWidth * 2 / 3
        }

        let relativeInZone = relativeX - zoneStart
        var accumulated: CGFloat = 0
        var foundIndex = zonePlacements.count

        for (index, placement) in zonePlacements.enumerated() {
            let placementWidth = CGFloat(placement.width) * cellWidth
            let midpoint = accumulated + placementWidth / 2
            if relativeInZone < midpoint {
                foundIndex = index
                break
            }
            accumulated += placementWidth
        }

        // Don't count as different position if dragging same widget
        if let dragId = draggedPlacementId,
           let draggedPlacement = allPlacements.first(where: { $0.id == dragId }),
           draggedPlacement.zone == zone {
            if foundIndex == draggedPlacement.orderInZone || foundIndex == draggedPlacement.orderInZone + 1 {
                // Same position, don't show drop target
                dropTargetIndex = nil
                return
            }
        }

        dropTargetIndex = foundIndex
    }

    func endDrag() -> Bool {
        defer { clearDragState() }

        // Handle removal (dragged outside)
        if isDraggingOutside, let id = draggedPlacementId {
            remove(id: id)
            return true
        }

        guard let zone = dropTargetZone else { return false }
        let index = dropTargetIndex ?? placements(for: zone).count

        // Move existing placement
        if let id = draggedPlacementId {
            move(id: id, to: zone, at: index)
            return true
        }

        // Insert new widget from palette
        if let widgetId = draggedWidgetId {
            return insert(widgetId: widgetId, in: zone, at: index) != nil
        }

        return false
    }

    func cancelDrag() {
        clearDragState()
    }

    private func clearDragState() {
        draggedPlacementId = nil
        draggedWidgetId = nil
        dropTargetZone = nil
        dropTargetIndex = nil
        isDraggingOutside = false
    }

    // MARK: - Cell Calculations (Legacy Compatibility)

    func canPlace(width: Int, at cell: Int, excluding: UUID? = nil) -> Bool {
        // Always allow in zone-based system
        return true
    }

    func findSlot(for width: Int) -> Int? {
        // Return first cell - zone system handles placement
        return 0
    }

    func cellIndex(for x: CGFloat) -> Int {
        let adjustedX = x - horizontalPadding
        let cell = Int(adjustedX / cellWidth)
        return max(0, min(cell, totalCells - 1))
    }

    func frame(for placement: WidgetPlacement) -> CGRect {
        // Calculate frame based on zone position
        var xOffset: CGFloat = horizontalPadding
        let zonePlacements = placements(for: placement.zone)

        // Add zone offset
        switch placement.zone {
        case .left:
            break // Starts at padding
        case .center:
            let leftWidth = leftPlacements.reduce(0) { $0 + $1.width }
            let centerWidth = centerPlacements.reduce(0) { $0 + $1.width }
            let rightWidth = rightPlacements.reduce(0) { $0 + $1.width }
            let totalUsed = leftWidth + centerWidth + rightWidth
            let availableGap = totalCells - totalUsed
            xOffset += CGFloat(leftWidth + availableGap / 2) * cellWidth
        case .right:
            let rightWidth = rightPlacements.reduce(0) { $0 + $1.width }
            xOffset = containerFrame.width - horizontalPadding - CGFloat(rightWidth) * cellWidth
        }

        // Add offset for widgets before this one in the zone
        for p in zonePlacements {
            if p.id == placement.id { break }
            xOffset += CGFloat(p.width) * cellWidth
        }

        return CGRect(
            x: xOffset,
            y: 0,
            width: CGFloat(placement.width) * cellWidth,
            height: barHeight
        )
    }

    // MARK: - Container Geometry

    func updateContainerGeometry(frame: CGRect, padding: CGFloat, height: CGFloat) {
        self.containerFrame = frame
        self.horizontalPadding = padding
        self.barHeight = height
    }

    func isInsideBar(_ location: CGPoint) -> Bool {
        let expandedFrame = containerFrame.insetBy(dx: -20, dy: -30)
        return expandedFrame.contains(location)
    }

    // MARK: - Config Sync

    func loadFromConfig() {
        let config = ConfigStore.shared.config
        let zonedLayout = config.zonedLayout

        leftPlacements = zonedLayout.left.enumerated().map { index, item in
            WidgetPlacement(
                id: item.instanceId,
                widgetId: item.widgetId,
                zone: .left,
                orderInZone: index
            )
        }

        centerPlacements = zonedLayout.center.enumerated().map { index, item in
            WidgetPlacement(
                id: item.instanceId,
                widgetId: item.widgetId,
                zone: .center,
                orderInZone: index
            )
        }

        rightPlacements = zonedLayout.right.enumerated().map { index, item in
            WidgetPlacement(
                id: item.instanceId,
                widgetId: item.widgetId,
                zone: .right,
                orderInZone: index
            )
        }
    }

    func saveToConfig() {
        let leftItems = leftPlacements.map { placement in
            ZonedWidgetItem(
                widgetId: placement.widgetId,
                instanceId: placement.id,
                order: placement.orderInZone,
                priority: WidgetRegistry.widget(for: placement.widgetId)?.defaultPriority ?? 50
            )
        }

        let centerItems = centerPlacements.map { placement in
            ZonedWidgetItem(
                widgetId: placement.widgetId,
                instanceId: placement.id,
                order: placement.orderInZone,
                priority: WidgetRegistry.widget(for: placement.widgetId)?.defaultPriority ?? 50
            )
        }

        let rightItems = rightPlacements.map { placement in
            ZonedWidgetItem(
                widgetId: placement.widgetId,
                instanceId: placement.id,
                order: placement.orderInZone,
                priority: WidgetRegistry.widget(for: placement.widgetId)?.defaultPriority ?? 50
            )
        }

        ConfigManager.shared.updateZonedLayout(
            left: leftItems,
            center: centerItems,
            right: rightItems
        )

        // Also update legacy widget order for backwards compatibility
        let allWidgetIds = (leftPlacements + centerPlacements + rightPlacements).map { $0.widgetId }
        ConfigManager.shared.updateWidgetOrder(allWidgetIds)

        hasUnsavedChanges = false
    }

    private func loadDefaultLayout() {
        let defaultLayout = ZonedLayout.default

        leftPlacements = defaultLayout.left.enumerated().map { index, item in
            WidgetPlacement(
                id: UUID(),
                widgetId: item.widgetId,
                zone: .left,
                orderInZone: index
            )
        }

        centerPlacements = defaultLayout.center.enumerated().map { index, item in
            WidgetPlacement(
                id: UUID(),
                widgetId: item.widgetId,
                zone: .center,
                orderInZone: index
            )
        }

        rightPlacements = defaultLayout.right.enumerated().map { index, item in
            WidgetPlacement(
                id: UUID(),
                widgetId: item.widgetId,
                zone: .right,
                orderInZone: index
            )
        }
    }
}
