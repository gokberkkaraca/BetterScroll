import Foundation
import IOKit.hid

struct MouseError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum BluetoothMouseModel: UInt16, CaseIterable {
    case master2S = 0xb019
    case master3 = 0xb023
    case master3S = 0xb034
    case master4 = 0xb042
    case master4Business = 0xb048

    var name: String {
        switch self {
        case .master2S: return "MX Master 2S"
        case .master3: return "MX Master 3"
        case .master3S: return "MX Master 3S"
        case .master4: return "MX Master 4"
        case .master4Business: return "MX Master 4 for Business"
        }
    }

    var smartShift: SmartShiftProtocol {
        switch self {
        case .master4, .master4Business: return .enhanced
        case .master2S, .master3, .master3S: return .original
        }
    }
}

enum SmartShiftProtocol: UInt16 {
    case original = 0x2110
    case enhanced = 0x2111

    var readMode: UInt8 { self == .enhanced ? 1 : 0 }
    var writeMode: UInt8 { readMode + 1 }
}

// All HID input and command continuations run on the main run loop.
final class Mouse {
    let device: IOHIDDevice
    let model: BluetoothMouseModel
    private var sequence: UInt8 = 0
    private var expected: (UInt8, UInt8)?
    private var reply: CheckedContinuation<[UInt8], Error>?
    private var timeout: DispatchWorkItem?
    var notification: ((UInt8, UInt8, [UInt8]) -> Void)?
    private(set) var connected = true

    init(_ device: IOHIDDevice, model: BluetoothMouseModel) {
        self.device = device
        self.model = model
    }

    func disconnect() {
        connected = false
        finish(.failure(MouseError("Mouse disconnected")))
    }

    private func finish(_ result: Result<[UInt8], Error>) {
        timeout?.cancel()
        expected = nil
        let pending = reply
        reply = nil
        pending?.resume(with: result)
    }

    func receive(_ b: [UInt8]) {
        guard b.count == 20, b[0] == 0x11, b[1] == 0xff else { return }
        if b[2] == 0xff, let (feature, command) = expected, b[3] == feature, b[4] == command {
            finish(.failure(MouseError("Mouse rejected command (code \(b[5]))")))
        } else if b[3] & 15 == 0 {
            notification?(b[2], b[3] >> 4, Array(b.dropFirst(4)))
        } else if let (feature, command) = expected, b[2] == feature, b[3] == command {
            finish(.success(Array(b.dropFirst(4))))
        }
    }

    func send(_ feature: UInt8, _ function: UInt8, _ args: [UInt8] = []) throws {
        var packet: [UInt8] = [0x11, 0xff, feature, function] + args
        packet += Array(repeating: 0, count: 20 - packet.count)
        let code = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, packet, packet.count)
        if code == kIOReturnNotPermitted {
            throw MouseError("macOS denied mouse access. Quit and reopen BetterScroll. If it persists, check Input Monitoring.")
        }
        guard code == kIOReturnSuccess else { throw MouseError("HID write failed (\(code))") }
    }

    @MainActor func call(_ feature: UInt8, _ function: UInt8, _ args: [UInt8] = []) async throws -> [UInt8] {
        guard connected, reply == nil else { throw MouseError("Mouse unavailable") }
        sequence = sequence % 15 + 1
        let command = function << 4 | sequence
        return try await withCheckedThrowingContinuation { continuation in
            expected = (feature, command)
            reply = continuation
            let timer = DispatchWorkItem { [weak self] in
                self?.finish(.failure(MouseError("Mouse did not respond. Wake it and retry.")))
            }
            timeout = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timer)
            do { try send(feature, command, args) }
            catch { finish(.failure(error)) }
        }
    }

    @MainActor func feature(_ id: UInt16) async throws -> UInt8 {
        let data = try await call(0, 0, [UInt8(id >> 8), UInt8(truncatingIfNeeded: id)])
        guard data[0] != 0 else { throw MouseError(String(format: "Missing mouse feature %04X", id)) }
        return data[0]
    }
}

final class Discovery {
    let manager = IOHIDManagerCreate(nil, 0)
    private var available: [Mouse] = []
    var mouse: Mouse? { available.first }
    var changed: ((Mouse?) -> Void)?

    func start() -> IOReturn {
        let matches = BluetoothMouseModel.allCases.map {
            [kIOHIDVendorIDKey: 0x046d, kIOHIDProductIDKey: Int($0.rawValue)]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ptr, result, _, device in
            guard let ptr, result == kIOReturnSuccess,
                  let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber,
                  let model = BluetoothMouseModel(rawValue: product.uint16Value) else { return }
            let owner = Unmanaged<Discovery>.fromOpaque(ptr).takeUnretainedValue()
            guard !owner.available.contains(where: { $0.device == device }) else { return }
            owner.available.append(Mouse(device, model: model))
            if owner.available.count == 1 { owner.changed?(owner.mouse) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ptr, _, _, device in
            guard let ptr else { return }
            let owner = Unmanaged<Discovery>.fromOpaque(ptr).takeUnretainedValue()
            guard let index = owner.available.firstIndex(where: { $0.device == device }) else { return }
            owner.available.remove(at: index).disconnect()
            if index == 0 { owner.changed?(owner.mouse) }
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { ptr, result, sender, _, id, bytes, count in
            guard let ptr, result == kIOReturnSuccess, id == 0x11, count == 20 else { return }
            guard let mouse = Unmanaged<Discovery>.fromOpaque(ptr).takeUnretainedValue().mouse,
                  sender == Unmanaged.passUnretained(mouse.device).toOpaque() else { return }
            mouse.receive(Array(UnsafeBufferPointer(start: bytes, count: count)))
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        return IOHIDManagerOpen(manager, 0)
    }
}
