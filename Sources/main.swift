import AppKit
import Carbon.HIToolbox
import IOKit.hid
import ServiceManagement
import SwiftUI

let modeButton: UInt8 = 0xc4
let buttons: [(UInt8, String)] = [(0x52, "Middle click"), (0x53, "Back button"), (0x56, "Forward button"),
                                   (0xc3, "Thumb gesture button"), (modeButton, "Wheel mode button")]
let actions = ["Mouse default", "Go back", "Go forward", "Copy", "Paste", "New tab", "Close tab"]
let thumb: UInt8 = 0xc3
let systemGestures: [(String, CGKeyCode)] = [("Mission Control", 126), ("App Exposé", 125), ("Previous Space", 123), ("Next Space", 124)]
let gestureChoices = ["No action"] + systemGestures.map { $0.0 } + actions.dropFirst()
let gesturesAction = actions.count
let modes = ["Ratchet", "Free-spin", "SmartShift"]
let defaults = UserDefaults.standard

func shortcut(_ action: Int) {
    let keys: [CGKeyCode] = [0, 33, 30, 8, 9, 17, 13]
    guard keys.indices.contains(action), action > 0 else { return }
    postKey(keys[action], flags: .maskCommand)
}

func performGesture(_ input: ThumbInput) {
    let action = input.mapping(in: defaults)
    if let (_, key) = systemGestures.first(where: { $0.0 == action }) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let strokes = controlArrowStrokes(key)
        let events = strokes.compactMap { code, down, flags -> CGEvent? in
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            return event
        }
        guard events.count == strokes.count else { return }
        for event in events { event.post(tap: .cghidEventTap) }
    } else if let index = actions.firstIndex(of: action) {
        shortcut(index)
    }
}

func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}

enum DeviceStatus {
    case waiting, contacting, connected, error(String)

    var message: String {
        switch self {
        case .waiting: return "Waiting for Bluetooth connection"
        case .contacting: return "Contacting mouse…"
        case .connected: return "Connected via Bluetooth"
        case .error(let message): return message
        }
    }
}

enum SettingAction {
    case smooth, reverse, mode(Int), button(UInt8, Int), gesture(ThumbInput, String)
    case updates, hideMenuBarIcon, quit, accessibility, inputMonitoring
}

final class App: NSObject, NSApplicationDelegate, ObservableObject {
    let discovery = Discovery()
    let scroll = Scroller()
    let popover = NSPopover()
    var item: NSStatusItem!
    @Published var status = DeviceStatus.waiting
    @Published var checkingUpdates = false
    #if SPARKLE_UPDATES
    private var inAppUpdater: InAppUpdater?
    #endif
    @Published var busy = false
    var wheel: UInt8 = 0, smart: UInt8 = 0, controls: UInt8 = 0
    var multiplier = 1
    var originalWheel: UInt8?
    var originals: [UInt8: UInt8] = [:]
    var gesture: ThumbGesture?
    var pressed = Set<UInt8>()
    var pendingModePresses = 0
    @Published var currentMode = -1
    var smartThreshold: UInt8 = 16
    var smooth: Bool { defaults.object(forKey: "smooth") as? Bool ?? true }
    var reverse: Bool { defaults.bool(forKey: "reverse") }
    let probe = CommandLine.arguments.contains("--probe")

    private var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if let event {
            return event.eventID == kAEOpenApplication
                && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        }
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !probe {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.isVisible = !defaults.bool(forKey: "hideMenuBarIcon") || !launchedAtLogin
            if item.isVisible { defaults.removeObject(forKey: "hideMenuBarIcon") }
            let icon = NSImage(named: "MenuMouse")
            icon?.size = NSSize(width: 20, height: 20)
            icon?.isTemplate = true
            icon?.accessibilityDescription = "BetterScroll"
            item.button?.image = icon
            item.button?.target = self
            item.button?.action = #selector(toggleSettings)
            item.button?.toolTip = "BetterScroll"
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: SettingsPanel(app: self))
        }
        discovery.changed = { [weak self] mouse in
            guard let self else { return }
            self.scroll.stop()
            self.gesture = nil
            self.wheel = 0; self.smart = 0; self.controls = 0
            self.originalWheel = nil; self.originals.removeAll(); self.pressed.removeAll()
            self.pendingModePresses = 0
            self.currentMode = -1; self.busy = false
            self.smartThreshold = 16
            self.status = .waiting
            if let mouse { self.configure(mouse) }
        }
        let result = discovery.start()
        if result != kIOReturnSuccess { status = .error("HID access unavailable (\(result)). Check Input Monitoring.") }
        if probe {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { print(self.status.message); exit(1) }
        }
    }

    func run(_ mouse: Mouse, _ task: @escaping @MainActor () async throws -> Void = {}) {
        guard !busy else { return }
        busy = true
        status = .contacting
        Task { @MainActor in
            do {
                try await task()
                while discovery.mouse === mouse && pendingModePresses > 0 {
                    pendingModePresses -= 1
                    try await applyMode(mouse, (currentMode + 1) % modes.count)
                }
                guard discovery.mouse === mouse else { return }
                status = .connected
            } catch {
                guard discovery.mouse === mouse else { return }
                pendingModePresses = 0
                status = .error(error.localizedDescription)
                if probe { print(status.message); exit(1) }
            }
            busy = false
        }
    }

    func configure(_ mouse: Mouse) {
        run(mouse) { [self] in
            let access = IOHIDDeviceOpen(mouse.device, 0)
            guard access == kIOReturnSuccess else {
                throw MouseError("Cannot open \(mouse.model.name) (\(access)). Enable Input Monitoring and reopen the app.")
            }
            wheel = try await mouse.feature(0x2121)
            let smartShift = mouse.model.smartShift
            smart = try await mouse.feature(smartShift.rawValue)
            controls = try await mouse.feature(0x1b04)
            multiplier = Int(try await mouse.call(wheel, 0)[0])
            guard multiplier > 0 else { throw MouseError("Invalid wheel resolution") }
            let old = try await mouse.call(wheel, 1)[0]
            let state = try await mouse.call(smart, smartShift.readMode)
            currentMode = state[0] == 1 ? 1 : (state[1] == 255 ? 0 : 2)
            let minimum: UInt8 = smartShift == .enhanced ? 1 : 8
            if (minimum..<255).contains(state[1]) { smartThreshold = state[1] }
            if probe { print("\(mouse.model.name) · Bluetooth HID++ OK · wheel multiplier \(multiplier) · \(modes[currentMode])"); exit(0) }
            // Keep the mouse's resolution and direction, but return scroll events to macOS on quit.
            if originalWheel == nil { originalWheel = old & 6 }
            mouse.notification = { [weak self] feature, event, data in self?.handle(feature, event, data) }
            try await applyWheel(mouse)
            for (cid, _) in buttons {
                let flags = try await mouse.call(controls, 2, [0, cid])[2]
                let mask: UInt8 = cid == thumb ? 0x11 : 1
                if originals[cid] == nil { originals[cid] = flags & mask }
                let desired = buttonDiversion(cid)
                if desired != flags & mask { try await applyButton(mouse, cid) }
            }
            if let preferred = defaults.object(forKey: "mode") as? Int, modes.indices.contains(preferred) {
                try await applyMode(mouse, preferred)
            }
        }
    }

    @MainActor func applyMode(_ mouse: Mouse, _ mode: Int) async throws {
        let params: [UInt8] = [mode == 1 ? 1 : 2, mode == 2 ? smartThreshold : (mode == 0 ? 255 : 0), 0]
        let result = try await mouse.call(smart, mouse.model.smartShift.writeMode, params)
        guard result[0] == params[0], params[1] == 0 || result[1] == params[1] else {
            throw MouseError("Mouse did not confirm the requested wheel mode")
        }
        currentMode = mode
        defaults.set(mode, forKey: "mode")
    }

    @MainActor func applyWheel(_ mouse: Mouse) async throws {
        guard let originalWheel else { return }
        scroll.stop()
        let mode: UInt8 = smooth && AXIsProcessTrusted() ? 3 : (originalWheel ^ (reverse ? 4 : 0))
        let response = try await mouse.call(wheel, 2, [mode])
        guard response[0] == mode else { throw MouseError("Mouse did not confirm scroll settings") }
    }

    func action(for cid: UInt8) -> Int {
        defaults.object(forKey: "button\(cid)") as? Int ?? (cid == thumb ? gesturesAction : 0)
    }

    func buttonDiversion(_ cid: UInt8) -> UInt8 {
        if cid == modeButton { return 1 }
        let action = action(for: cid)
        guard action > 0, AXIsProcessTrusted() else { return originals[cid] ?? 0 }
        return cid == thumb && action == gesturesAction ? 0x11 : 1
    }

    @MainActor func applyButton(_ mouse: Mouse, _ cid: UInt8) async throws {
        let diversion = buttonDiversion(cid)
        try await setReporting(mouse, cid, diversion)
        if cid == thumb { gesture = nil }
    }

    @MainActor func setReporting(_ mouse: Mouse, _ cid: UInt8, _ flags: UInt8) async throws {
        let update: UInt8 = cid == thumb ? 0x22 : 2
        _ = try await mouse.call(controls, 3, [0, cid, update | flags, 0, 0])
    }

    func handle(_ feature: UInt8, _ event: UInt8, _ data: [UInt8]) {
        if feature == wheel && event == 0 {
            let delta = Int16(bitPattern: UInt16(data[1]) << 8 | UInt16(data[2]))
            let resolution = data[0] & 0x10 == 0 ? 1 : multiplier
            let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
            let invert = natural != reverse
            scroll.add(Double(delta) * (invert ? -48 : 48) / Double(resolution))
        } else if feature == controls && event == 1 {
            if let direction = gesture?.move(data) { performGesture(direction) }
        } else if feature == controls && event == 0 {
            var held = Set<UInt8>()
            for i in stride(from: 0, to: 8, by: 2) where data[i] == 0 && data[i + 1] != 0 { held.insert(data[i + 1]) }
            for cid in held.subtracting(pressed) {
                if cid == modeButton, let mouse = discovery.mouse {
                    pendingModePresses += 1
                    if !busy { run(mouse) }
                } else if cid == thumb && action(for: cid) == gesturesAction { gesture = ThumbGesture() }
                else { shortcut(action(for: cid)) }
            }
            if !held.contains(thumb), let completed = gesture {
                if !completed.fired { performGesture(.tap) }
                gesture = nil
            }
            pressed = held
        }
    }

    @objc func toggleSettings() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            objectWillChange.send()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
            guard let content = popover.contentViewController?.view, let window = content.window,
                  let buttonWindow = button.window else { return }

            // AppKit can place a status-item popover over the menu bar even with the bottom edge requested.
            let buttonBottom = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)).minY
            let menuBottom = min(buttonBottom, buttonWindow.screen?.visibleFrame.maxY ?? buttonBottom)
            let contentTop = window.convertToScreen(content.convert(content.bounds, to: nil)).maxY
            if contentTop > menuBottom - 4 {
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY - (contentTop - menuBottom + 4)))
            }
            window.makeKey()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        item?.isVisible = true
        defaults.removeObject(forKey: "hideMenuBarIcon")
        return false
    }

    @MainActor func select(_ setting: SettingAction) {
        switch setting {
        case .updates:
            guard !checkingUpdates else { return }
            popover.performClose(nil)
            #if SPARKLE_UPDATES
            if inAppUpdater == nil, let installer = try? InAppUpdater() {
                inAppUpdater = installer
                installer.updater.publisher(for: \.sessionInProgress).assign(to: &$checkingUpdates)
            }
            if let inAppUpdater {
                NSApp.activate(ignoringOtherApps: true)
                inAppUpdater.updater.checkForUpdates()
                return
            }
            #endif
            checkingUpdates = true
            Task { @MainActor in
                await Updates.check()
                checkingUpdates = false
            }
        case .hideMenuBarIcon:
            popover.performClose(nil)
            defaults.set(true, forKey: "hideMenuBarIcon")
            item?.isVisible = false
        case .quit:
            NSApp.terminate(nil)
        case .accessibility:
            popover.performClose(nil)
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            popover.performClose(nil)
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        case .gesture(let input, let choice):
            objectWillChange.send()
            defaults.set(choice, forKey: input.preferenceKey)
        case .smooth, .reverse, .mode, .button:
            guard let mouse = discovery.mouse else { return }
            run(mouse) { [self] in
                switch setting {
                case .smooth, .reverse:
                    let key: String
                    let old: Bool
                    if case .smooth = setting { (key, old) = ("smooth", smooth) }
                    else { (key, old) = ("reverse", reverse) }
                    defaults.set(!old, forKey: key)
                    do { try await applyWheel(mouse) }
                    catch { defaults.set(old, forKey: key); throw error }
                case .mode(let index):
                    try await applyMode(mouse, index)
                case .button(let cid, let index):
                    let key = "button\(cid)"
                    let old = defaults.object(forKey: key)
                    defaults.set(index, forKey: key)
                    do { try await applyButton(mouse, cid) }
                    catch { defaults.set(old, forKey: key); throw error }
                default: break
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let mouse = discovery.mouse, originalWheel != nil || busy else { return .terminateNow }
        Task { @MainActor in
            while busy && discovery.mouse === mouse { try? await Task.sleep(nanoseconds: 30_000_000) }
            if discovery.mouse === mouse {
                busy = true
                if let originalWheel { _ = try? await mouse.call(wheel, 2, [originalWheel]) }
                for (cid, original) in originals where buttonDiversion(cid) != original {
                    try? await setReporting(mouse, cid, original)
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

let application = NSApplication.shared
let delegate = App()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
