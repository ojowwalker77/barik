import Combine
import Foundation

struct DiagnosticMessage: Identifiable, Equatable {
    enum Kind: String {
        case config
        case wm
        case update
    }

    let id: String
    let kind: Kind
    let title: String
    let message: String
}

final class AppDiagnostics: ObservableObject {
    static let shared = AppDiagnostics()

    @Published private(set) var messages: [DiagnosticMessage] = []

    private init() {}

    func post(id: String, kind: DiagnosticMessage.Kind, title: String, message: String) {
        let update = {
            let diagnostic = DiagnosticMessage(id: id, kind: kind, title: title, message: message)
            if let index = self.messages.firstIndex(where: { $0.id == id }) {
                if self.messages[index] == diagnostic {
                    return
                }
                self.messages[index] = diagnostic
            } else {
                self.messages.append(diagnostic)
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    func clear(id: String) {
        let clearBlock = {
            self.messages.removeAll { $0.id == id }
        }

        if Thread.isMainThread {
            clearBlock()
        } else {
            DispatchQueue.main.async(execute: clearBlock)
        }
    }
}
