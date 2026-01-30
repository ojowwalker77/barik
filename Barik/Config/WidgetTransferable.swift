import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Custom UTType for Barik widgets
extension UTType {
    static var barikWidget: UTType {
        UTType(exportedAs: "com.barik.widget")
    }

    static var barikDefaultSet: UTType {
        UTType(exportedAs: "com.barik.widget.defaultset")
    }
}

/// Represents a widget instance that can be dragged and dropped
/// Uses instanceId to allow multiple instances of the same widget (e.g., spacers)
struct DraggableWidget: Identifiable, Codable, Hashable {
    let instanceId: UUID
    let widgetId: String

    var id: UUID { instanceId }

    init(widgetId: String, instanceId: UUID = UUID()) {
        self.instanceId = instanceId
        self.widgetId = widgetId
    }

    /// Create from existing TomlWidgetItem
    init(from tomlItem: TomlWidgetItem) {
        self.instanceId = UUID()
        self.widgetId = tomlItem.id
    }

    /// Get the widget definition from the registry
    var definition: WidgetDefinition? {
        WidgetRegistry.widget(for: widgetId)
    }

    /// Convert to TomlWidgetItem for config/rendering
    func toTomlWidgetItem() -> TomlWidgetItem {
        TomlWidgetItem(id: widgetId, inlineParams: [:])
    }
}

extension DraggableWidget: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .barikWidget)
    }
}

/// Represents the default widget set for drag-to-reset
struct DefaultSetTransferable: Codable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .barikDefaultSet)
    }
}
