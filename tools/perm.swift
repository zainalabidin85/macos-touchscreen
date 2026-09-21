import IOKit.hid
let s = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
print("InputMonitoring:", s == kIOHIDAccessTypeGranted ? "granted" : s == kIOHIDAccessTypeDenied ? "DENIED" : "not determined")
