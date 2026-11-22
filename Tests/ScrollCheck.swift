import Foundation
import CoreGraphics

@main struct Check {
    static func main() {
        for productID: UInt16 in [0xb042, 0xb048] {
            let smartShift = BluetoothMouseModel(rawValue: productID)!.smartShift
            precondition(smartShift.rawValue == 0x2111 && smartShift.readMode == 1 && smartShift.writeMode == 2)
        }
        for productID: UInt16 in [0xb019, 0xb023, 0xb034] {
            let smartShift = BluetoothMouseModel(rawValue: productID)!.smartShift
            precondition(smartShift.rawValue == 0x2110 && smartShift.readMode == 0 && smartShift.writeMode == 1)
        }
        precondition(Updates.components("1.0.0") == [1, 0, 0])
        precondition(Updates.components("1.0.9")!.lexicographicallyPrecedes(Updates.components("1.0.10")!))
        for bad in ["1.0", "-1.0.0", "1..2", "1.0.0-beta"] { precondition(Updates.components(bad) == nil) }
        for rate in [60, 120, 144] {
            for distance in [-720.0, -3.2, 3.2, 48, 720] {
                var tail = ScrollTail()
                tail.add(distance)
                var sum = 0
                for _ in 0..<rate {
                    let step = Int(tail.step(seconds: 1 / Double(rate)))
                    precondition(Double(step) * distance >= 0)
                    sum += step
                }
                precondition(sum == Int(distance.rounded()) && tail.remaining == 0)
            }
        }
        for (dx, dy, direction): (Int16, Int16, ThumbInput) in [(-45, 0, .left), (45, -2, .right), (0, -45, .up), (1, 45, .down)] {
            var gesture = ThumbGesture()
            let packet = [dx, dy].flatMap { [UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] }
            precondition(gesture.move(packet) == nil && !gesture.fired)
            precondition(gesture.move(packet) == direction && gesture.fired)
            precondition(gesture.move(packet) == nil)
        }
        let suite = "better-scroll-check-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        for input in ThumbInput.allCases {
            let old = input.mapping(in: preferences)
            preferences.set("No action", forKey: input.preferenceKey)
            precondition(input.mapping(in: preferences) == "No action")
            precondition(ThumbInput.allCases.filter { $0 != input }.allSatisfy { $0.mapping(in: preferences) != "No action" })
            preferences.removeObject(forKey: input.preferenceKey)
            precondition(input.mapping(in: preferences) == old)
        }
        print("All four thumb directions, jitter threshold and single action per hold passed")
        for key: CGKeyCode in [123, 124, 125, 126] {
            let strokes = controlArrowStrokes(key)
            let arrows: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            precondition(strokes.map(\.key) == [59, key, key, 59])
            precondition(strokes.map(\.down) == [true, true, false, false])
            precondition(strokes.map(\.flags) == [.maskControl, arrows, arrows, []])
        }
        print("Control-arrow event sequence checks passed")
        var tail = ScrollTail()
        tail.add(480); tail.add(-48)
        precondition(tail.remaining == -48)
        print("Scroll distance, settling and reversal checks passed")
    }
}
