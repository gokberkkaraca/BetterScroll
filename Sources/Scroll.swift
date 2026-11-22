import AppKit

struct ScrollTail {
    var remaining = 0.0
    private var fraction = 0.0

    mutating func add(_ pixels: Double) {
        if pixels * remaining < 0 { remaining = 0; fraction = 0 }
        remaining += pixels
    }

    mutating func step(seconds: Double) -> Int32 {
        let movement = abs(remaining) < 0.5 ? remaining : remaining * (1 - exp(-seconds / 0.035))
        remaining -= movement
        fraction += movement
        let whole = Int32(fraction.rounded())
        fraction -= Double(whole)
        return whole
    }
}

final class Scroller {
    var tail = ScrollTail()
    private var timer: Timer?
    private var last = 0.0

    func add(_ pixels: Double) {
        tail.add(pixels)
        guard timer == nil else { return }
        last = ProcessInfo.processInfo.systemUptime
        let rate = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.maximumFramesPerSecond ?? 60
        let clock = Timer(timeInterval: 1 / Double(max(60, min(rate, 240))), repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = tail.step(seconds: now - last)
        last = now
        if delta != 0 {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: delta, wheel2: 0, wheel3: 0)
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event?.flags = CGEventSource.flagsState(.combinedSessionState)
            event?.post(tap: .cghidEventTap)
        }
        if tail.remaining == 0 { timer?.invalidate(); timer = nil }
    }

    func stop() { timer?.invalidate(); timer = nil; tail = ScrollTail() }
}
