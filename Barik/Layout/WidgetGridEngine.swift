import Foundation
import SwiftUI

/// Single placement = widget + start cell position
struct WidgetPlacement: Identifiable, Equatable {
    let id: UUID
    let widgetId: String
    var startCell: Int

    var width: Int {
        WidgetRegistry.widget(for: widgetId)?.gridWidth ?? 2
    }

    var occupiedCells: Range<Int> {
        startCell..<(startCell + width)
    }

    init(id: UUID = UUID(), widgetId: String, startCell: Int) {
        self.id = id
        self.widgetId = widgetId
        self.startCell = startCell
    }
}

/// Layout engine using fixed cell grid for widget positioning
@Observable
final class WidgetGridEngine {
    static let shared = WidgetGridEngine()

    // MARK: - Configuration

    let totalCells: Int = 20

    // MARK: - State

    private(set) var placements: [WidgetPlacement] = []

    var isCustomizing: Bool = false
    var hasUnsavedChanges: Bool = false

    /// Currently dragged placement (nil if dragging from palette)
    var draggedPlacementId: UUID?

    /// Widget ID being dragged (for palette drags)
    var draggedWidgetId: String?

    /// Target cell for drop (nil if invalid)
    var dropTargetCell: Int?

    /// Whether currently dragging outside the bar (for removal)
    var isDraggingOutside: Bool = false

    // MARK: - Undo

    private var undoStack: [[WidgetPlacement]] = []
    private var originalPlacements: [WidgetPlacement]?

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

    private init() {}

    // MARK: - Computed Properties

    /// Set of all currently occupied cells
    var occupiedCells: Set<Int> {
        Set(placements.flatMap { Array($0.occupiedCells) })
    }

    /// The dragged placement (if any)
    var draggedPlacement: WidgetPlacement? {
        guard let id = draggedPlacementId else { return nil }
        return placements.first { $0.id == id }
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

    // MARK: - Cell Calculations

    /// Check if cells are free for placement
    func canPlace(width: Int, at cell: Int, excluding: UUID? = nil) -> Bool {
        let needed = cell..<(cell + width)
        guard needed.lowerBound >= 0, needed.upperBound <= totalCells else { return false }

        for placement in placements where placement.id != excluding {
            let occupied = placement.occupiedCells
            // Check for intersection
            if occupied.overlaps(needed) {
                return false
            }
        }
        return true
    }

    /// Find first available slot for given width
    func findSlot(for width: Int) -> Int? {
        for cell in 0...(totalCells - width) {
            if canPlace(width: width, at: cell) {
                return cell
            }
        }
        return nil
    }

    /// Convert screen X position to cell index
    func cellIndex(for x: CGFloat) -> Int {
        let adjustedX = x - horizontalPadding
        let cell = Int(adjustedX / cellWidth)
        return max(0, min(cell, totalCells - 1))
    }

    /// Get frame for a placement
    func frame(for placement: WidgetPlacement) -> CGRect {
        let x = horizontalPadding + CGFloat(placement.startCell) * cellWidth
        return CGRect(x: x, y: 0, width: CGFloat(placement.width) * cellWidth, height: barHeight)
    }

    // MARK: - Mutations

    private func recordState() {
        undoStack.append(placements)
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }

    @discardableResult
    func insert(widgetId: String, at cell: Int) -> WidgetPlacement? {
        let width = WidgetRegistry.widget(for: widgetId)?.gridWidth ?? 2
        guard canPlace(width: width, at: cell) else { return nil }

        recordState()
        let placement = WidgetPlacement(id: UUID(), widgetId: widgetId, startCell: cell)
        placements.append(placement)
        placements.sort { $0.startCell < $1.startCell }
        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        return placement
    }

    func move(id: UUID, to cell: Int) {
        guard let index = placements.firstIndex(where: { $0.id == id }) else { return }
        let width = placements[index].width
        guard canPlace(width: width, at: cell, excluding: id) else { return }

        recordState()
        placements[index].startCell = cell
        placements.sort { $0.startCell < $1.startCell }
        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func remove(id: UUID) {
        guard placements.contains(where: { $0.id == id }) else { return }
        recordState()
        placements.removeAll { $0.id == id }
        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    func resetToDefaults() {
        recordState()
        loadDefaultLayout()
        hasUnsavedChanges = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        placements = previous
        hasUnsavedChanges = (originalPlacements.map { placements != $0 }) ?? true
    }

    // MARK: - Customization Mode

    func startCustomizing() {
        loadFromConfig()
        undoStack.removeAll()
        originalPlacements = placements
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
        if let original = originalPlacements {
            placements = original
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
        dropTargetCell = nil
    }

    func beginDragFromPalette(widgetId: String) {
        draggedPlacementId = nil
        draggedWidgetId = widgetId
        isDraggingOutside = false
        dropTargetCell = nil
    }

    func updateDrag(location: CGPoint, isOutside: Bool) {
        isDraggingOutside = isOutside

        if isOutside {
            dropTargetCell = nil
            return
        }

        let targetCell = cellIndex(for: location.x)
        let width = draggedWidth

        // Snap to valid position
        let adjustedTarget = min(targetCell, totalCells - width)
        let excludeId = draggedPlacementId

        if canPlace(width: width, at: adjustedTarget, excluding: excludeId) {
            dropTargetCell = adjustedTarget
        } else {
            // Try to find nearest valid cell
            dropTargetCell = findNearestValidCell(from: adjustedTarget, width: width, excluding: excludeId)
        }
    }

    func endDrag() -> Bool {
        defer { clearDragState() }

        // Handle removal (dragged outside)
        if isDraggingOutside, let id = draggedPlacementId {
            remove(id: id)
            return true
        }

        guard let targetCell = dropTargetCell else { return false }

        // Move existing placement
        if let id = draggedPlacementId {
            move(id: id, to: targetCell)
            return true
        }

        // Insert new widget from palette
        if let widgetId = draggedWidgetId {
            return insert(widgetId: widgetId, at: targetCell) != nil
        }

        return false
    }

    func cancelDrag() {
        clearDragState()
    }

    private func clearDragState() {
        draggedPlacementId = nil
        draggedWidgetId = nil
        dropTargetCell = nil
        isDraggingOutside = false
    }

    private func findNearestValidCell(from start: Int, width: Int, excluding: UUID?) -> Int? {
        // Search outward from start position
        for offset in 0..<totalCells {
            let leftCell = start - offset
            let rightCell = start + offset

            if leftCell >= 0 && canPlace(width: width, at: leftCell, excluding: excluding) {
                return leftCell
            }
            if rightCell <= totalCells - width && canPlace(width: width, at: rightCell, excluding: excluding) {
                return rightCell
            }
        }
        return nil
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
        let items = ConfigManager.shared.config.rootToml.widgets.displayed
        var cell = 0
        placements = []

        for item in items {
            let width = WidgetRegistry.widget(for: item.id)?.gridWidth ?? 2
            let placement = WidgetPlacement(id: UUID(), widgetId: item.id, startCell: cell)
            placements.append(placement)
            cell += width
        }
    }

    func saveToConfig() {
        let widgetIds = placements.sorted { $0.startCell < $1.startCell }.map { $0.widgetId }
        ConfigManager.shared.updateWidgetOrder(widgetIds)
        hasUnsavedChanges = false
    }

    private func loadDefaultLayout() {
        var cell = 0
        placements = []

        for widgetId in WidgetRegistry.defaultLayout {
            let width = WidgetRegistry.widget(for: widgetId)?.gridWidth ?? 2
            let placement = WidgetPlacement(id: UUID(), widgetId: widgetId, startCell: cell)
            placements.append(placement)
            cell += width
        }
    }
}
