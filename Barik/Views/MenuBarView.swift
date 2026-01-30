import SwiftUI

struct MenuBarView: View {
    let monitorName: String?
    @ObservedObject var configManager = ConfigManager.shared
    @Bindable var engine = WidgetGridEngine.shared

    @State private var poofLocation: CGPoint?
    @State private var showOverflowMenu = false

    init(monitorName: String? = nil) {
        self.monitorName = monitorName
    }

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let position = configManager.config.experimental.foreground.position
        let padding = configManager.config.experimental.foreground.horizontalPadding
        let foreground = configManager.config.experimental.foreground
        let barHeight = max(foreground.resolveHeight(), 1.0)

        let alignment: Alignment = switch position {
        case .top: .top
        case .bottom: .bottom
        }

        HStack(spacing: 0) {
            if engine.isCustomizing {
                customizationModeContent(barHeight: barHeight)
            } else {
                normalModeContent(barHeight: barHeight)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, padding)
        .background(GeometryReader { geo in
            Color.black.opacity(0.001)
                .onAppear {
                    engine.updateContainerGeometry(
                        frame: geo.frame(in: .global),
                        padding: padding,
                        height: barHeight
                    )
                }
                .onChange(of: geo.frame(in: .global)) { _, newFrame in
                    engine.updateContainerGeometry(
                        frame: newFrame,
                        padding: padding,
                        height: barHeight
                    )
                }
        })
        .preferredColorScheme(theme)
        // Unified drop handling for customization
        .onDrop(of: [.barikWidget, .barikDefaultSet], delegate: BarDropDelegate(
            engine: engine
        ))
        // Poof animation overlay
        .overlay {
            if let poof = poofLocation {
                PoofEffect(at: poof)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            poofLocation = nil
                        }
                    }
            }
        }
    }

    // MARK: - Normal Mode Content

    @ViewBuilder
    private func normalModeContent(barHeight: CGFloat) -> some View {
        let foreground = configManager.config.experimental.foreground
        let spacing = foreground.spacing

        // Build set of widgets to hide based on config flags
        let widgetsToHide: Set<String> = {
            var set = Set<String>()
            if !foreground.showClock { set.insert("default.time") }
            if !foreground.showBattery { set.insert("default.battery") }
            if !foreground.showNetwork { set.insert("default.network") }
            return set
        }()

        // 3-zone layout with true center alignment
        HStack(spacing: 0) {
            // Left Zone - expands to fill, content aligned leading
            ZoneView(
                zone: .left,
                monitorName: monitorName,
                spacing: spacing,
                widgetsToHide: widgetsToHide,
                configManager: configManager
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center Zone - stays in true center
            ZoneView(
                zone: .center,
                monitorName: monitorName,
                spacing: spacing,
                widgetsToHide: widgetsToHide,
                configManager: configManager
            )

            // Right Zone - expands to fill, content aligned trailing
            ZoneView(
                zone: .right,
                monitorName: monitorName,
                spacing: spacing,
                widgetsToHide: widgetsToHide,
                configManager: configManager
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Overflow menu button if there are hidden widgets
            if !engine.overflowWidgets.isEmpty {
                OverflowMenuButton(
                    overflowWidgets: engine.overflowWidgets,
                    monitorName: monitorName,
                    configManager: configManager
                )
            }

            // System banner (if not in widgets)
            if !engine.allPlacements.contains(where: { $0.widgetId == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
            }
        }

        Spacer()

        SettingsWidget()
    }

    // MARK: - Customization Mode Content

    @ViewBuilder
    private func customizationModeContent(barHeight: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Cell grid background (subtle guides during drag)
            CellGridOverlay(engine: engine, barHeight: barHeight)

            // 3-zone layout for customization
            HStack(spacing: 0) {
                // Left Zone
                CustomizationZoneView(
                    zone: .left,
                    engine: engine,
                    barHeight: barHeight,
                    onRemove: handleRemove
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center Zone
                CustomizationZoneView(
                    zone: .center,
                    engine: engine,
                    barHeight: barHeight,
                    onRemove: handleRemove
                )
                .frame(maxWidth: .infinity, alignment: .center)

                // Right Zone
                CustomizationZoneView(
                    zone: .right,
                    engine: engine,
                    barHeight: barHeight,
                    onRemove: handleRemove
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Drop target indicator
            if let targetZone = engine.dropTargetZone, let targetIndex = engine.dropTargetIndex {
                DropTargetHighlight(
                    zone: targetZone,
                    index: targetIndex,
                    engine: engine,
                    barHeight: barHeight
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Settings widget (dimmed during customization)
        SettingsWidget()
            .opacity(0.3)
            .disabled(true)
    }

    private func handleRemove(_ placement: WidgetPlacement, _ frame: CGRect) {
        poofLocation = CGPoint(x: frame.midX, y: frame.midY)
        withAnimation(.spring(duration: 0.2)) {
            engine.remove(id: placement.id)
        }
    }
}

// MARK: - Zone View (Normal Mode)

struct ZoneView: View {
    let zone: Zone
    let monitorName: String?
    let spacing: CGFloat
    let widgetsToHide: Set<String>
    let configManager: ConfigManager

    @Bindable var engine = WidgetGridEngine.shared

    var body: some View {
        let placements = engine.placements(for: zone).filter {
            !widgetsToHide.contains($0.widgetId)
        }

        HStack(spacing: spacing) {
            ForEach(placements) { placement in
                buildWidgetView(for: placement.widgetId)
            }
        }
    }

    @ViewBuilder
    private func buildWidgetView(for widgetId: String) -> some View {
        let item = TomlWidgetItem(id: widgetId, inlineParams: [:])
        let config = ConfigProvider(config: configManager.resolvedWidgetConfig(for: item))

        switch widgetId {
        case "default.spaces":
            SpacesWidget(monitorName: monitorName).environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager.shared).environmentObject(config)

        case "default.nowplaying":
            NowPlayingWidget().environmentObject(config)

        case "default.bluetooth":
            BluetoothWidget()

        case "spacer":
            Spacer().frame(minWidth: 50, maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color.active)
                .frame(width: 2, height: 15)
                .clipShape(Capsule())

        case "system-banner":
            SystemBannerWidget()

        case "default.settings":
            EmptyView()

        default:
            Text("?\(widgetId)?").foregroundColor(.red)
        }
    }
}

// MARK: - Customization Zone View

struct CustomizationZoneView: View {
    let zone: Zone
    @Bindable var engine: WidgetGridEngine
    let barHeight: CGFloat
    let onRemove: (WidgetPlacement, CGRect) -> Void

    @ObservedObject var configManager = ConfigManager.shared

    var body: some View {
        let placements = engine.placements(for: zone)

        HStack(spacing: 4) {
            ForEach(placements) { placement in
                EditablePlacementView(
                    placement: placement,
                    content: buildWidgetView(for: placement.widgetId),
                    engine: engine,
                    barHeight: barHeight,
                    onRemove: onRemove
                )
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(zoneHighlightColor)
                .opacity(isDropTarget ? 0.3 : 0.1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTarget ? Color.accentColor : Color.gray.opacity(0.3),
                    lineWidth: isDropTarget ? 2 : 1,
                    antialiased: true
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDropTarget)
    }

    private var isDropTarget: Bool {
        engine.dropTargetZone == zone
    }

    private var zoneHighlightColor: Color {
        switch zone {
        case .left: return .blue
        case .center: return .green
        case .right: return .orange
        }
    }

    @ViewBuilder
    private func buildWidgetView(for widgetId: String) -> some View {
        let item = TomlWidgetItem(id: widgetId, inlineParams: [:])
        let config = ConfigProvider(config: configManager.resolvedWidgetConfig(for: item))

        switch widgetId {
        case "default.spaces":
            SpacesWidget(monitorName: nil).environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager.shared).environmentObject(config)

        case "default.nowplaying":
            NowPlayingWidget().environmentObject(config)

        case "default.bluetooth":
            BluetoothWidget()

        case "spacer":
            HStack {
                Spacer()
            }
            .frame(maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color.active)
                .frame(width: 2, height: 15)
                .clipShape(Capsule())

        case "system-banner":
            SystemBannerWidget()

        case "default.settings":
            EmptyView()

        default:
            Text("?\(widgetId)?").foregroundColor(.red)
        }
    }
}

// MARK: - Overflow Menu Button

struct OverflowMenuButton: View {
    let overflowWidgets: [WidgetPlacement]
    let monitorName: String?
    let configManager: ConfigManager

    @State private var showMenu = false

    var body: some View {
        Button {
            showMenu.toggle()
        } label: {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hidden Widgets")
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach(overflowWidgets) { placement in
                    HStack(spacing: 8) {
                        if let definition = WidgetRegistry.widget(for: placement.widgetId) {
                            Image(systemName: definition.icon)
                                .frame(width: 20)
                            Text(definition.name)
                        } else {
                            Text(placement.widgetId)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .frame(minWidth: 150)
        }
    }
}

// MARK: - Cell Grid Overlay

struct CellGridOverlay: View {
    let engine: WidgetGridEngine
    let barHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            // Draw subtle cell boundaries when dragging
            guard engine.draggedPlacementId != nil || engine.draggedWidgetId != nil else { return }

            let cellWidth = engine.cellWidth
            for i in 0...engine.totalCells {
                let x = CGFloat(i) * cellWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 4))
                path.addLine(to: CGPoint(x: x, y: barHeight - 4))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Drop Target Highlight

struct DropTargetHighlight: View {
    let zone: Zone
    let index: Int
    @Bindable var engine: WidgetGridEngine
    let barHeight: CGFloat

    private func calculateXOffset(totalWidth: CGFloat) -> CGFloat {
        let zoneWidth = totalWidth / 3

        let zoneStart: CGFloat
        switch zone {
        case .left: zoneStart = 0
        case .center: zoneStart = zoneWidth
        case .right: zoneStart = zoneWidth * 2
        }

        // Calculate x position within zone
        let placements = engine.placements(for: zone)
        var xOffset: CGFloat = 0
        for (i, placement) in placements.enumerated() {
            if i >= index { break }
            xOffset += CGFloat(placement.width) * engine.cellWidth
        }

        return zoneStart + xOffset - 2
    }

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 4, height: barHeight - 8)
                .offset(x: calculateXOffset(totalWidth: geo.size.width), y: 4)
                .animation(.spring(duration: 0.2), value: index)
                .animation(.spring(duration: 0.2), value: zone)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Editable Placement View

struct EditablePlacementView<Content: View>: View {
    let placement: WidgetPlacement
    let content: Content
    @Bindable var engine: WidgetGridEngine
    let barHeight: CGFloat
    let onRemove: (WidgetPlacement, CGRect) -> Void

    @State private var isHovered = false
    @State private var placementFrame: CGRect = .zero

    private var isBeingDragged: Bool {
        engine.draggedPlacementId == placement.id
    }

    var body: some View {
        content
            .fixedSize()
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { placementFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        placementFrame = newFrame
                    }
            })
            .overlay(alignment: .topTrailing) {
                // X button for removal on hover
                if isHovered && engine.draggedPlacementId == nil && engine.draggedWidgetId == nil {
                    Button {
                        onRemove(placement, placementFrame)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .opacity(isBeingDragged ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isBeingDragged)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
            .draggable(DraggableWidget(widgetId: placement.widgetId, instanceId: placement.id)) {
                WidgetDragPreview(widgetId: placement.widgetId)
                    .onAppear {
                        engine.beginDragFromBar(placementId: placement.id)
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    }
            }
    }
}

// MARK: - Widget Drag Preview

struct WidgetDragPreview: View {
    let widgetId: String

    var body: some View {
        let definition = WidgetRegistry.widget(for: widgetId)

        HStack(spacing: 6) {
            if let def = definition {
                Image(systemName: def.icon)
                    .font(.system(size: 14))
                Text(def.name)
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text(widgetId)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Poof Effect

struct PoofEffect: View {
    let position: CGPoint
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0

    init(at position: CGPoint) {
        self.position = position
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.8),
                        Color.gray.opacity(0.4),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 20
                )
            )
            .frame(width: 40, height: 40)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.5
                    opacity = 0
                }
            }
    }
}
