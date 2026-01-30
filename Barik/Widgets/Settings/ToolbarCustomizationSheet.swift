import SwiftUI

/// Safari-style toolbar customization palette
/// The actual editing happens on the menu bar - this is just the widget palette
struct ToolbarCustomizationSheet: View {
    @Bindable var engine = WidgetGridEngine.shared
    @Environment(\.dismiss) private var dismiss

    let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            VStack(spacing: 16) {
                // Instructions
                Text("Drag items to the toolbar above, or drag items off the toolbar to remove them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                Divider()

                // Position section - separate from widget customization
                PositionSection()

                Divider()

                // Available widgets section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    // Widget palette
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(availableWidgets) { definition in
                                PaletteItem(definition: definition, engine: engine)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(duration: 0.25), value: availableWidgets.map(\.id))
                    }
                    .frame(maxHeight: 200)
                }

                Divider()

                // Default set
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drag the default set to restore defaults")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    DefaultSetItem(engine: engine)
                }

                Divider()

                // Edit config button
                HStack {
                    Button {
                        openConfigFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                            Text("Edit Config File...")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(width: 380, height: 460)
        .background(.regularMaterial)
    }

    /// Get widgets available to add (not already in toolbar unless allowMultiple)
    private var availableWidgets: [WidgetDefinition] {
        let currentIds = engine.placements.map { $0.widgetId }
        return WidgetRegistry.available(excluding: currentIds)
    }

    private func openConfigFile() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path1 = "\(homePath)/.barik-config.toml"
        let path2 = "\(homePath)/.config/barik/config.toml"

        let configPath: String
        if FileManager.default.fileExists(atPath: path1) {
            configPath = path1
        } else if FileManager.default.fileExists(atPath: path2) {
            configPath = path2
        } else {
            configPath = path1
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    private var header: some View {
        HStack {
            Text("Customize Toolbar")
                .font(.headline)

            Spacer()

            if engine.canUndo {
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        engine.undo()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Palette Item

struct PaletteItem: View {
    let definition: WidgetDefinition
    @Bindable var engine: WidgetGridEngine
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: definition.icon)
                .font(.title2)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.12))
                )

            Text(definition.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 70, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isDragging ? 0.9 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(duration: 0.2), value: isHovered)
        .animation(.spring(duration: 0.2), value: isDragging)
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(DraggableWidget(widgetId: definition.id)) {
            PaletteItemDragPreview(definition: definition)
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
            // Double-click to add at first available slot
            if let slot = engine.findSlot(for: definition.gridWidth) {
                withAnimation(.spring(duration: 0.25)) {
                    _ = engine.insert(widgetId: definition.id, at: slot)
                }
            }
        }
    }
}

// MARK: - Palette Item Drag Preview

struct PaletteItemDragPreview: View {
    let definition: WidgetDefinition

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: definition.icon)
                .font(.system(size: 12))
            Text(definition.name)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

// MARK: - Default Set Item

struct DefaultSetItem: View {
    @Bindable var engine: WidgetGridEngine
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WidgetRegistry.defaultLayout.prefix(5), id: \.self) { widgetId in
                if let def = WidgetRegistry.widget(for: widgetId) {
                    Image(systemName: def.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Text("...")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.gray.opacity(0.12) : Color.gray.opacity(0.08))
        )
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.spring(duration: 0.2), value: isDragging)
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

// MARK: - Position Section

struct PositionSection: View {
    @ObservedObject private var configManager = ConfigManager.shared

    private var position: BarPosition {
        configManager.config.experimental.foreground.position
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bar Position")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            Picker("Position", selection: positionBinding) {
                Text("Top").tag("top")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
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
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12))
            Text("Default Set")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}
