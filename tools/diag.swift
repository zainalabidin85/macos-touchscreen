import IOKit.hid
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(m, nil)   // all devices
func name(_ d: IOHIDDevice) -> String {
    (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "?"
}
let matched: IOHIDDeviceCallback = { _, _, _, d in
    print("matched:", name(d), "vid", IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) ?? "", "pid", IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) ?? "")
}
IOHIDManagerRegisterDeviceMatchingCallback(m, matched, nil)
let rep: IOHIDReportCallback = { _, _, sender, _, id, bytes, len in
    let d = Unmanaged<IOHIDDevice>.fromOpaque(sender!).takeUnretainedValue()
    let hex = (0..<min(len, 24)).map { String(format: "%02x", bytes[$0]) }.joined(separator: " ")
    print("report:", name(d), "id", id, "len", len, hex)
}
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096 * 64)
IOHIDManagerRegisterInputReportCallback(m, rep, nil)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("open:", String(IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)), radix: 16))
CFRunLoopRun()
