import Foundation
import CoreGraphics

/// Result of completing a drag operation
struct DragResult {
    let success: Bool
    let affectedPlacementId: UUID?
}
