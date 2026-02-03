import AppKit
import SwiftUI

/// Safari-style toolbar customization palette
struct ToolbarCustomizationSheet: View {
    @Bindable var engine = WidgetGridEngine.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Form {
                ZoneLayoutSection(engine: engine)
                AvailableWidgetsSection(engine: engine)
                RestoreSection(engine: engine)
                ConfigSection()
            }
            .formStyle(.grouped)
            .padding(.horizontal, 12)
            .groupBoxStyle(PlainGroupBoxStyle())
        }
        .frame(width: 640, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Customize Toolbar")
                    .font(.title2.weight(.semibold))
                Text("Drag items to the toolbar above, or drag them off to remove.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if engine.canUndo {
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        engine.undo()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Undo")
            }

            if engine.hasUnsavedChanges {
                Button("Cancel") {
                    engine.cancelCustomizing()
                    SettingsWindowController.shared.closeWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Done") {
                engine.finishCustomizing()
                SettingsWindowController.shared.closeWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Zone Layout Section

struct ZoneLayoutSection: View {
    @Bindable var engine: WidgetGridEngine

    var body: some View {
        GroupBox("Zones") {
            VStack(spacing: 12) {
                ZoneRow(zone: .left, engine: engine)
                ZoneRow(zone: .center, engine: engine)
                ZoneRow(zone: .right, engine: engine)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Zone Row

struct ZoneRow: View {
    let zone: Zone
    @Bindable var engine: WidgetGridEngine

    private var zoneName: String {
        zone.rawValue.uppercased()
    }

    private var zoneColor: Color {
        switch zone {
        case .left: return Color.blue.opacity(0.35)
        case .center: return Color.green.opacity(0.35)
        case .right: return Color.orange.opacity(0.35)
        }
    }

    private var fillPercentage: Double {
        engine.fillPercentage(for: zone)
    }

    private var widgetCount: Int {
        engine.placements(for: zone).count
    }

    var body: some View {
        LabeledContent(zoneName.capitalized) {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                        Capsule()
                            .fill(zoneColor)
                            .frame(width: max(6, geo.size.width * min(fillPercentage, 1.0)))
                    }
                }
                .frame(width: 110, height: 6)

                Text("\(widgetCount) widget\(widgetCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .trailing)
            }
        }
        .font(.callout)
    }
}

// MARK: - Available Widgets Section

struct AvailableWidgetsSection: View {
    @Bindable var engine: WidgetGridEngine

    private var availableWidgets: [WidgetDefinition] {
        let currentIds = engine.allPlacements.map { $0.widgetId }
        return WidgetRegistry.available(excluding: currentIds)
            .filter { $0.id != "spacer" }  // Hide flexible space
    }

    var body: some View {
        GroupBox("Available Widgets") {
            if availableWidgets.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("All widgets are in use")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(availableWidgets) { definition in
                        WidgetCard(definition: definition, engine: engine)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.25), value: availableWidgets.map(\.id))
            }
        }
    }
}

// MARK: - Widget Card (Horizontal Layout)

struct WidgetCard: View {
    let definition: WidgetDefinition
    @Bindable var engine: WidgetGridEngine
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: definition.icon)
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            // Name only
            Text(definition.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.25) : Color.clear)
        )
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(DraggableWidget(widgetId: definition.id)) {
            PaletteDragPreview(definition: definition)
                .onAppear {
                    isDragging = true
                    engine.beginDragFromPalette(widgetId: definition.id)
                }
                .onDisappear {
                    isDragging = false
                    engine.cancelDrag()
                }
        }
        .onTapGesture(count: 2) {
            withAnimation(.spring(duration: 0.25)) {
                _ = engine.insert(widgetId: definition.id, in: definition.defaultZone)
            }
        }
    }
}

// MARK: - Palette Drag Preview

struct PaletteDragPreview: View {
    let definition: WidgetDefinition

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: definition.icon)
                .font(.system(size: 14))
            Text(definition.name)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Restore Section

struct RestoreSection: View {
    @Bindable var engine: WidgetGridEngine
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        GroupBox("Restore") {
            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Layout")
                        .font(.callout.weight(.medium))
                    Text("Drag to toolbar or click to reset")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(WidgetRegistry.defaultLayout.prefix(4), id: \.self) { widgetId in
                        if let def = WidgetRegistry.widget(for: widgetId) {
                            Image(systemName: def.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.25) : Color.clear)
            )
            .opacity(isDragging ? 0.5 : 1.0)
            .scaleEffect(isDragging ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .onHover { hovering in
                isHovered = hovering
            }
            .draggable(DefaultSetTransferable()) {
                DefaultSetDragPreview()
                    .onAppear { isDragging = true }
                    .onDisappear { isDragging = false }
            }
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    engine.resetToDefaults()
                }
            }
        }
    }
}

// MARK: - Config Section

struct ConfigSection: View {
    var body: some View {
        GroupBox("Config") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        openConfigFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12))
                            Text("Edit Config File…")
                                .font(.callout)
                        }
                    }
                    .buttonStyle(.link)

                    Text(ConfigManager.shared.configFilePathForDisplay)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contextMenu {
                            Button("Copy Path") {
                                copyConfigPath()
                            }
                        }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Position")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BarPositionPicker()
                }
            }
            .padding(.top, 4)
        }
    }

    private func openConfigFile() {
        guard let url = ConfigManager.shared.configFileURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyConfigPath() {
        let path = ConfigManager.shared.configFilePathForDisplay
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

// MARK: - Bar Position Picker (Compact)

struct BarPositionPicker: View {
    @ObservedObject private var configManager = ConfigManager.shared

    private var position: BarPosition {
        configManager.config.experimental.foreground.position
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: positionBinding) {
                Text("Top").tag("top")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .controlSize(.mini)
        }
    }

    private var positionBinding: Binding<String> {
        Binding(
            get: { position.rawValue },
            set: { ConfigManager.shared.updateConfigValue(key: "experimental.foreground.position", newValue: $0) }
        )
    }
}

// MARK: - Default Set Drag Preview

struct DefaultSetDragPreview: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14))
            Text("Default Layout")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

// MARK: - Styles

private struct PlainGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.caption)
                .foregroundStyle(.secondary)
            configuration.content
        }
        .padding(.vertical, 10)
    }
}
