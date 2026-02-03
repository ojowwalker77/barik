import Foundation
import SwiftUI

typealias ConfigData = [String: AnyCodableValue]
typealias BarPosition = BarikConfig.ForegroundSettings.Position

final class ConfigProvider: ObservableObject {
    @Published var config: ConfigData

    init(config: ConfigData) {
        self.config = config
    }
}
