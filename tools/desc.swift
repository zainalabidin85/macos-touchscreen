import IOKit.hid
import Foundation
let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(m, [kIOHIDDeviceUsagePageKey: 0x0d, kIOHIDDeviceUsageKey: 0x04] as CFDictionary)
IOHIDManagerOpen(m, 0)
for d in (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? [] {
    func p(_ k: String) -> String { "\(IOHIDDeviceGetProperty(d, k as CFString) ?? "?" as CFTypeRef)" }
    print("== interface usagePage", p(kIOHIDPrimaryUsagePageKey), "maxIn", p(kIOHIDMaxInputReportSizeKey), "maxFeat", p(kIOHIDMaxFeatureReportSizeKey))
    if let data = IOHIDDeviceGetProperty(d, kIOHIDReportDescriptorKey as CFString) as? Data {
        print(data.map { String(format: "%02x", $0) }.joined(separator: " "))
    }
    for e in (IOHIDDeviceCopyMatchingElements(d, nil, 0) as? [IOHIDElement]) ?? [] {
        let t = IOHIDElementGetType(e)
        if t == kIOHIDElementTypeFeature {
            print(String(format: "feature: page 0x%02x usage 0x%02x id %d", IOHIDElementGetUsagePage(e), IOHIDElementGetUsage(e), IOHIDElementGetReportID(e)))
        }
    }
}
