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

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Instructions
                    Text("Drag items to the toolbar above, or drag them off to remove.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    // Zone Layout Cards
                    ZoneLayoutSection(engine: engine)

                    // Available Widgets
                    AvailableWidgetsSection(engine: engine)

                    // Reset & Config
                    BottomActionsSection(engine: engine)
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 560)
        .background(.regularMaterial)
    }

    /// Get widgets available to add (not already in toolbar unless allowMultiple)
    private var availableWidgets: [WidgetDefinition] {
        let currentIds = engine.allPlacements.map { $0.widgetId }
        return WidgetRegistry.available(excluding: currentIds)
    }

    private var header: some View {
        HStack {
            Text("Customize Toolbar")
                .font(.system(size: 15, weight: .semibold))

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
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Undo")
            }

            if engine.hasUnsavedChanges {
                Button("Cancel") {
                    engine.cancelCustomizing()
                    SettingsWindowController.shared.closeWindow()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button("Done") {
                engine.finishCustomizing()
                SettingsWindowController.shared.closeWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Zone Layout Section

struct ZoneLayoutSection: View {
    @Bindable var engine: WidgetGridEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ZONES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            HStack(spacing: 12) {
                ZoneCard(zone: .left, engine: engine)
                ZoneCard(zone: .center, engine: engine)
                ZoneCard(zone: .right, engine: engine)
            }
        }
    }
}

// MARK: - Zone Card

struct ZoneCard: View {
    let zone: Zone
    @Bindable var engine: WidgetGridEngine

    private var zoneName: String {
        zone.rawValue.uppercased()
    }

    private var zoneColor: Color {
        switch zone {
        case .left: return .blue
        case .center: return .green
        case .right: return .orange
        }
    }

    private var fillPercentage: Double {
        engine.fillPercentage(for: zone)
    }

    private var widgetCount: Int {
        engine.placements(for: zone).count
    }

    var body: some View {
        VStack(spacing: 8) {
            // Zone name
            Text(zoneName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            // Capacity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [zoneColor, zoneColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * min(fillPercentage, 1.0)))
                }
            }
            .frame(height: 10)

            // Widget count
            Text("\(widgetCount) widget\(widgetCount == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(zoneColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(zoneColor.opacity(0.2), lineWidth: 1)
                )
        )
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
        VStack(alignment: .leading, spacing: 12) {
            Text("AVAILABLE WIDGETS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

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
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.06))
                )
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
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                )

            // Name only
            Text(definition.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.gray.opacity(0.12) : Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
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
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

// MARK: - Bottom Actions Section

struct BottomActionsSection: View {
    @Bindable var engine: WidgetGridEngine
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 16) {
            // Restore defaults
            VStack(alignment: .leading, spacing: 8) {
                Text("RESTORE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Layout")
                            .font(.system(size: 12, weight: .medium))
                        Text("Drag to toolbar or click to reset")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mini preview of defaults
                    HStack(spacing: 4) {
                        ForEach(WidgetRegistry.defaultLayout.prefix(4), id: \.self) { widgetId in
                            if let def = WidgetRegistry.widget(for: widgetId) {
                                Image(systemName: def.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isHovered ? Color.gray.opacity(0.12) : Color.gray.opacity(0.06))
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

            // Config file button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        openConfigFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                            Text("Edit Config File...")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Text(ConfigManager.shared.configFilePathForDisplay)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contextMenu {
                            Button("Copy Path") {
                                copyConfigPath()
                            }
                        }
                }

                Spacer()

                // Bar position picker (compact)
                BarPositionPicker()
            }
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
            Text("Position:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Picker("", selection: positionBinding) {
                Text("Top").tag("top")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .controlSize(.small)
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
