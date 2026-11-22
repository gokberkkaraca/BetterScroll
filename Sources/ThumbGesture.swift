import Foundation
import Carbon.HIToolbox
import CoreGraphics

func controlArrowStrokes(_ key: CGKeyCode) -> [(key: CGKeyCode, down: Bool, flags: CGEventFlags)] {
    let control = CGKeyCode(kVK_Control)
    // macOS global shortcuts expect Control key transitions and the flags of a physical arrow key.
    let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
    return [
        (control, true, .maskControl), (key, true, arrowFlags),
        (key, false, arrowFlags), (control, false, []),
    ]
}

enum ThumbInput: String, CaseIterable {
    case tap, up, down, left, right

    var preferenceKey: String { "thumbGesture.\(rawValue)" }

    func mapping(in preferences: UserDefaults) -> String {
        if let saved = preferences.string(forKey: preferenceKey) { return saved }
        switch self {
        case .tap, .up: return "Mission Control"
        case .down: return "App Exposé"
        case .left: return "Previous Space"
        case .right: return "Next Space"
        }
    }
}

// A fresh instance represents one hold. Commit once, after passing the jitter threshold.
struct ThumbGesture {
    private var x = 0, y = 0
    private(set) var fired = false

    mutating func move(_ data: [UInt8]) -> ThumbInput? {
        guard !fired, data.count >= 4 else { return nil }
        func delta(_ offset: Int) -> Int {
            Int(Int16(bitPattern: UInt16(data[offset]) << 8 | UInt16(data[offset + 1])))
        }
        x += delta(0)
        y += delta(2)
        guard max(abs(x), abs(y)) >= 80 else { return nil }
        fired = true
        if abs(x) > abs(y) { return x < 0 ? .left : .right }
        return y < 0 ? .up : .down
    }
}
