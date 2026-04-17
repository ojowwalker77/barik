import SwiftUI
import UniformTypeIdentifiers

/// Unified drop delegate for the widget bar using zone-based positioning
struct BarDropDelegate: DropDelegate {
    @Bindable var engine: WidgetGridEngine

    func validateDrop(info: DropInfo) -> Bool {
        guard engine.isCustomizing else { return false }
        return info.hasItemsConforming(to: [.barikWidget, .barikDefaultSet])
    }

    func dropEntered(info: DropInfo) {
        guard engine.isCustomizing else { return }

        // Handle default set
        if info.hasItemsConforming(to: [.barikDefaultSet]) {
            return
        }

        // Set up drag from palette if not already dragging from bar
        if engine.draggedPlacementId == nil && engine.draggedWidgetId == nil {
            // Load the widget info from the drag item
            let providers = info.itemProviders(for: [.barikWidget])
            for provider in providers {
                _ = provider.loadTransferable(type: DraggableWidget.self) { [engine] result in
                    DispatchQueue.main.async {
                        if case .success(let widget) = result {
                            engine.beginDragFromPalette(widgetId: widget.widgetId)
                        }
                    }
                }
            }
        }

        let globalLocation = engine.globalPoint(from: info.location)
        engine.updateDrag(location: globalLocation, isOutside: false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard engine.isCustomizing else { return DropProposal(operation: .cancel) }

        let globalLocation = engine.globalPoint(from: info.location)
        let isOutside = !isInsideDropZone(globalLocation)
        engine.updateDrag(location: globalLocation, isOutside: isOutside)

        if isOutside && engine.draggedPlacementId != nil {
            // Dragging existing widget outside = removal
            return DropProposal(operation: .move)
        }

        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard engine.isCustomizing else { return }
        let globalLocation = engine.globalPoint(from: info.location)
        engine.updateDrag(location: globalLocation, isOutside: true)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard engine.isCustomizing else { return false }

        defer {
            engine.cancelDrag()
        }

        // Handle DefaultSetTransferable (reset)
        if info.hasItemsConforming(to: [.barikDefaultSet]) {
            withAnimation(.spring(duration: 0.3)) {
                engine.resetToDefaults()
            }
            return true
        }

        // Handle DraggableWidget
        let providers = info.itemProviders(for: [.barikWidget])
        guard !providers.isEmpty else { return false }

        // If we have an active drag, use the engine's endDrag
        if engine.draggedPlacementId != nil || engine.draggedWidgetId != nil {
            return engine.endDrag()
        }

        // Otherwise, load from provider and insert
        let dropLocation = engine.globalPoint(from: info.location)
        for provider in providers {
            _ = provider.loadTransferable(type: DraggableWidget.self) { [engine] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let widget):
                        // Determine zone from drop location
                        let zone = engine.zoneForGlobalLocation(dropLocation)
                        withAnimation(.spring(duration: 0.25)) {
                            _ = engine.insert(widgetId: widget.widgetId, in: zone)
                        }
                    case .failure:
                        break
                    }
                }
            }
        }

        return true
    }

    private func isInsideDropZone(_ globalLocation: CGPoint) -> Bool {
        engine.isInsideBar(globalLocation)
    }
}
