import Foundation

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = AeroSpace
    let executablePath = ConfigManager.shared.config.aerospace.path

    func getSpacesWithWindows() -> [AeroSpace]? {
        guard var spaces = fetchSpaces(), let windows = fetchWindows() else {
            return nil
        }
        // Fetch focused space/window once (avoid redundant subprocess calls)
        let focusedSpace = fetchFocusedSpace()
        let focusedWindow = fetchFocusedWindow()

        if let focused = focusedSpace {
            for i in 0..<spaces.count {
                spaces[i].isFocused = (spaces[i].id == focused.id)
            }
        }

        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in windows {
            var mutableWindow = window
            if let focused = focusedWindow, window.id == focused.id {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let focused = focusedSpace {
                // Window without workspace goes to focused space
                if var space = spaceDict[focused.id] {
                    space.windows.append(mutableWindow)
                    spaceDict[focused.id] = space
                }
            }
        }
        var resultSpaces = Array(spaceDict.values)
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.id < $1.id }
        }
        return resultSpaces.filter { !$0.windows.isEmpty }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        // Skip if already focused (prevents redundant subprocess call)
        if let focused = fetchFocusedSpace(), focused.id == spaceId {
            return
        }
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) {
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private func fetchSpaces() -> [AeroSpace]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--all", "--json", "--format",
                "%{workspace} %{monitor-name}",
            ])
        else {
            return nil
        }
        return try? JSONDecoder().decode([AeroSpace].self, from: data)
    }

    private func fetchWindows() -> [AeroWindow]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{window-title} %{workspace}",
            ])
        else {
            return nil
        }
        return try? JSONDecoder().decode([AeroWindow].self, from: data)
    }

    private func fetchFocusedSpace() -> AeroSpace? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--focused", "--json",
            ])
        else {
            return nil
        }
        return try? JSONDecoder().decode([AeroSpace].self, from: data).first
    }

    private func fetchFocusedWindow() -> AeroWindow? {
        guard let data = runAerospaceCommand(arguments: [
            "list-windows", "--focused", "--json",
        ]),
              !data.isEmpty else {
            return nil
        }
        // Aerospace returns plain text "No window is focused" when no window is focused
        // Check if it starts with '[' (valid JSON array)
        guard data.first == UInt8(ascii: "[") else {
            return nil
        }
        return try? JSONDecoder().decode([AeroWindow].self, from: data).first
    }
}
