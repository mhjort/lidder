import Foundation

/// Renders the angle as a 30-cell bar, mapping 0–180 degrees onto it.
public func gauge(for angle: Double) -> String {
    let width = 30
    let clamped = max(0, min(180, angle))
    let filled = Int((clamped / 180.0) * Double(width))
    return String(repeating: "█", count: filled)
        + String(repeating: "░", count: width - filled)
}

/// A human-readable label for the angle.
public func describe(_ angle: Double) -> String {
    switch angle {
    case ..<5:   return "closed"
    case ..<45:  return "slightly open"
    case ..<90:  return "partially open"
    case ..<120: return "mostly open"
    default:     return "fully open"
    }
}
