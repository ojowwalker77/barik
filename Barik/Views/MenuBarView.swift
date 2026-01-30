import SwiftUI

struct MenuBarView: View {
    let monitorName: String?
    @ObservedObject var configManager = ConfigManager.shared
    @Bindable var engine = WidgetGridEngine.shared
    @State private var barFrame: CGRect = .zero
    @State private var poofLocation: CGPoint?

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
        let spacing = foreground.spacing
        let barHeight = max(foreground.resolveHeight(), 1.0)

        // Build set of widgets to hide based on config flags
        let widgetsToHide: Set<String> = {
            var set = Set<String>()
            if !foreground.showClock { set.insert("default.time") }
            if !foreground.showBattery { set.insert("default.battery") }
            if !foreground.showNetwork { set.insert("default.network") }
            return set
        }()
        let items = configManager.config.rootToml.widgets.displayed.filter {
            !widgetsToHide.contains($0.id)
        }

        let alignment: Alignment = switch position {
        case .top: .top
        case .bottom: .bottom
        }

        HStack(spacing: 0) {
            if engine.isCustomizing {
                // Customization mode: cell-based positioning with natural widget sizing
                ZStack(alignment: .leading) {
                    // Cell grid background (subtle guides during drag)
                    CellGridOverlay(engine: engine, barHeight: barHeight)

                    // Placements positioned by cell offset
                    ForEach(engine.placements) { placement in
                        EditablePlacementView(
                            placement: placement,
                            content: buildWidgetView(for: placement.widgetId),
                            engine: engine,
                            barHeight: barHeight,
                            onRemove: { removedPlacement, frame in
                                poofLocation = CGPoint(x: frame.midX, y: frame.midY)
                                withAnimation(.spring(duration: 0.2)) {
                                    engine.remove(id: removedPlacement.id)
                                }
                            }
                        )
                    }

                    // Drop target indicator
                    if let targetCell = engine.dropTargetCell {
                        DropTargetHighlight(
                            cell: targetCell,
                            width: engine.draggedWidth,
                            cellWidth: engine.cellWidth,
                            barHeight: barHeight,
                            padding: engine.horizontalPadding
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Normal mode: render from config
                HStack(spacing: spacing) {
                    ForEach(0..<items.count, id: \.self) { index in
                        let item = items[index]
                        buildView(for: item)
                    }

                    if !items.contains(where: { $0.id == "system-banner" }) {
                        SystemBannerWidget(withLeftPadding: true)
                    }
                }
            }

            Spacer()

            SettingsWidget()
                .opacity(engine.isCustomizing ? 0.3 : 1.0)
                .disabled(engine.isCustomizing)
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, padding)
        .background(GeometryReader { geo in
            Color.black.opacity(0.001)
                .onAppear {
                    barFrame = geo.frame(in: .global)
                    engine.updateContainerGeometry(
                        frame: geo.frame(in: .global),
                        padding: padding,
                        height: barHeight
                    )
                }
                .onChange(of: geo.frame(in: .global)) { _, newFrame in
                    barFrame = newFrame
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
            engine: engine,
            barFrame: barFrame
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

    @ViewBuilder
    private func buildView(for item: TomlWidgetItem) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.spaces":
            SpacesWidget(monitorName: monitorName).environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager.shared)
                .environmentObject(config)

        case "default.nowplaying":
            NowPlayingWidget()
                .environmentObject(config)

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
            EmptyView()  // Settings handled separately

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }

    /// Build widget view by ID (for customization mode)
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
    let cell: Int
    let width: Int
    let cellWidth: CGFloat
    let barHeight: CGFloat
    let padding: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
            )
            .frame(width: cellWidth * CGFloat(width), height: barHeight - 8)
            .offset(x: CGFloat(cell) * cellWidth, y: 0)
            .animation(.spring(duration: 0.2), value: cell)
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
            .fixedSize()  // Keep widget's intrinsic size (no cell-based frame)
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
            .offset(x: CGFloat(placement.startCell) * engine.cellWidth)  // Cell-based positioning
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
