import IOKit.hid
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
let mode = UInt8(CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 2 : 2)
let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 8146, kIOHIDProductIDKey: 24835, kIOHIDPrimaryUsagePageKey: 13] as CFDictionary)
IOHIDManagerOpen(m, 0)
guard let d = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>)?.first else { print("no digitizer"); exit(1) }

// read current mode
var cur = [UInt8](repeating: 0, count: 3); var len = 3
let g = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 7, &cur, &len)
print("get feature 7:", String(g, radix: 16), cur.map { String(format: "%02x", $0) })

var out: [UInt8] = [7, mode, 0]
let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 7, &out, out.count)
print("set mode \(mode):", String(r, radix: 16), r == kIOReturnSuccess ? "ok" : "FAILED")
len = 3
_ = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 7, &cur, &len)
print("readback:", cur.map { String(format: "%02x", $0) })

let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
IOHIDDeviceRegisterInputReportCallback(d, buf, 64, { _, _, _, _, id, bytes, n in
    print("touch report id", id, "len", n, (0..<min(n, 14)).map { String(format: "%02x", bytes[$0]) }.joined(separator: " "))
}, nil)
IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("listening 25s, touch the screen now")
CFRunLoopRunInMode(.defaultMode, 25, false)
print("done")
