import SwiftUI

struct SettingsPopup: View {
    @ObservedObject var configManager = ConfigManager.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                TabButton(title: "General", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(title: "Bar", isSelected: selectedTab == 1) { selectedTab = 1 }
                TabButton(title: "Advanced", isSelected: selectedTab == 2) { selectedTab = 2 }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case 0: GeneralTab(configManager: configManager)
                    case 1: BarTab(configManager: configManager)
                    case 2: AdvancedTab()
                    default: EmptyView()
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 360, height: 380)
        .background(.regularMaterial)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var configManager: ConfigManager

    private var theme: String {
        configManager.config.rootToml.theme ?? "system"
    }

    private var position: BarPosition {
        configManager.config.experimental.foreground.position
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Appearance") {
                HStack {
                    Text("Theme")
                    Spacer()
                    Picker("", selection: themeBinding) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            SettingsSection(title: "Layout") {
                HStack {
                    Text("Position")
                    Spacer()
                    Picker("", selection: positionBinding) {
                        Text("Top").tag("top")
                        Text("Bottom").tag("bottom")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
        }
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { theme },
            set: { ConfigManager.shared.updateConfigValue(key: "theme", newValue: $0) }
        )
    }

    private var positionBinding: Binding<String> {
        Binding(
            get: { position.rawValue },
            set: { ConfigManager.shared.updateConfigValue(key: "experimental.foreground.position", newValue: $0) }
        )
    }
}

// MARK: - Bar Tab

struct BarTab: View {
    @ObservedObject var configManager: ConfigManager

    private var backgroundDisplayed: Bool {
        configManager.config.experimental.background.displayed
    }

    private var widgetsBackgroundDisplayed: Bool {
        configManager.config.experimental.foreground.widgetsBackground.displayed
    }

    private var spacing: CGFloat {
        configManager.config.experimental.foreground.spacing
    }

    private var horizontalPadding: CGFloat {
        configManager.config.experimental.foreground.horizontalPadding
    }

    private var backgroundBlurRaw: Int {
        configManager.config.experimental.background.blurRaw
    }

    private var widgetBlurRaw: Int {
        configManager.config.experimental.foreground.widgetsBackground.blurRaw
    }

    @State private var backgroundBlur: Double = 3
    @State private var widgetBlur: Double = 3
    @State private var spacingValue: Double = 15
    @State private var paddingValue: Double = 25

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Background Panel") {
                Toggle(isOn: backgroundBinding) {
                    Text("Show background panel")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Blur: \(Int(backgroundBlur))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $backgroundBlur, in: 1...7, step: 1) { editing in
                        if !editing {
                            ConfigManager.shared.updateConfigValue(
                                key: "experimental.background.blur",
                                newValue: Int(backgroundBlur)
                            )
                        }
                    }
                }
            }

            SettingsSection(title: "Widget Backgrounds") {
                Toggle(isOn: widgetsBackgroundBinding) {
                    Text("Show widget backgrounds")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Blur: \(Int(widgetBlur))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $widgetBlur, in: 1...6, step: 1) { editing in
                        if !editing {
                            ConfigManager.shared.updateConfigValue(
                                key: "experimental.foreground.widgets-background.blur",
                                newValue: Int(widgetBlur)
                            )
                        }
                    }
                }
            }

            SettingsSection(title: "Spacing") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widget spacing: \(Int(spacingValue))px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $spacingValue, in: 0...50, step: 5) { editing in
                        if !editing {
                            ConfigManager.shared.updateConfigValue(
                                key: "experimental.foreground.spacing",
                                newValue: Int(spacingValue)
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Horizontal padding: \(Int(paddingValue))px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $paddingValue, in: 0...100, step: 5) { editing in
                        if !editing {
                            ConfigManager.shared.updateConfigValue(
                                key: "experimental.foreground.horizontal-padding",
                                newValue: Int(paddingValue)
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            backgroundBlur = Double(backgroundBlurRaw)
            widgetBlur = Double(widgetBlurRaw)
            spacingValue = Double(spacing)
            paddingValue = Double(horizontalPadding)
        }
    }

    private var backgroundBinding: Binding<Bool> {
        Binding(
            get: { backgroundDisplayed },
            set: { ConfigManager.shared.updateConfigValue(key: "experimental.background.displayed", newValue: $0) }
        )
    }

    private var widgetsBackgroundBinding: Binding<Bool> {
        Binding(
            get: { widgetsBackgroundDisplayed },
            set: { ConfigManager.shared.updateConfigValue(key: "experimental.foreground.widgets-background.displayed", newValue: $0) }
        )
    }
}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Configuration") {
                Text("Widget-specific settings (battery, time, spaces) must be configured in the config file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Config File") {
                    openConfigFile()
                }
                .buttonStyle(.borderedProminent)
            }

            SettingsSection(title: "Config File Location") {
                Text("~/.barik-config.toml")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
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
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
        }
    }
}
