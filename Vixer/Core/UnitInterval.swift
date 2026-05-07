import Foundation

enum UnitInterval {
    static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
