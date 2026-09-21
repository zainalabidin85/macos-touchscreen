// touchmouse: turn a HID touchscreen (LGD AIT / Melfas) into mouse input on macOS.
//
//   touchmouse --displays           list displays and their indexes
//   touchmouse --probe              print raw HID element values while you touch
//   touchmouse [--display N] [--invert-scroll]
//       tap = click, double-tap = double-click, drag = drag,
//       hold still 0.6s = right-click, two-finger drag = scroll
//
// Needs Input Monitoring + Accessibility permission for the app running it (Terminal).

import Cocoa
import IOKit.hid

let vendorID = 8146
let productID = 24835

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
let probe = args.contains("--probe")

func activeDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

if args.contains("--displays") {
    for (i, d) in activeDisplays().enumerated() {
        let b = CGDisplayBounds(d)
        print("[\(i)] id=\(d) \(Int(b.width))x\(Int(b.height)) at (\(Int(b.origin.x)),\(Int(b.origin.y)))"
              + (CGDisplayIsMain(d) != 0 ? " main" : "")
              + (CGDisplayIsBuiltin(d) != 0 ? " builtin" : ""))
    }
    exit(0)
}

var displayIndex = 0
if let i = args.firstIndex(of: "--display"), i + 1 < args.count, let n = Int(args[i + 1]) {
    displayIndex = n
} else if let m = activeDisplays().firstIndex(where: { CGDisplayIsMain($0) != 0 }) {
    displayIndex = m
}
let displays = activeDisplays()
guard displayIndex < displays.count else {
    print("no display with index \(displayIndex)"); exit(1)
}

// Per-finger state, keyed by the finger's HID collection.
struct Contact {
    var x = 0.0, y = 0.0   // normalized 0...1
    var tip = false
}
var contacts: [Int: Contact] = [:]

// Gestures:
//   one finger, lift          -> click (two quick taps -> double-click)
//   one finger, move          -> drag
//   one finger, hold still    -> right-click
//   two fingers, move         -> scroll
enum Mode { case idle, pending, dragging, scrolling, consumed }
var mode = Mode.idle
var primaryKey = 0
var startPoint = CGPoint.zero
var lastPoint = CGPoint.zero
var lastTapTime = Date.distantPast
var lastTapPoint = CGPoint.zero
var clickCount: Int64 = 1
var longPressTimer: Timer?
var scrollCentroid = CGPoint.zero
var scrollRemainder = CGPoint.zero

let dragThreshold = 12.0          // points a finger may wander before a tap becomes a drag
let longPressDelay = 0.6          // seconds
let scrollDirection = args.contains("--invert-scroll") ? -1.0 : 1.0

func point(_ c: Contact) -> CGPoint {
    let b = CGDisplayBounds(displays[displayIndex])
    return CGPoint(x: b.origin.x + c.x * b.width, y: b.origin.y + c.y * b.height)
}

func post(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1, button: CGMouseButton = .left) {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}

func centroid(_ fingers: [Contact]) -> CGPoint {
    let pts = fingers.map(point)
    return CGPoint(x: pts.map(\.x).reduce(0, +) / Double(pts.count),
                   y: pts.map(\.y).reduce(0, +) / Double(pts.count))
}

func cancelLongPress() { longPressTimer?.invalidate(); longPressTimer = nil }

func beginScroll(_ fingers: [Contact]) {
    cancelLongPress()
    mode = .scrolling
    scrollCentroid = centroid(fingers)
    scrollRemainder = .zero
    post(.mouseMoved, scrollCentroid)     // scroll events go to whatever is under the cursor
}

func update() {
    let down = contacts.filter { $0.value.tip }
    let fingers = down.map(\.value)

    switch mode {
    case .idle:
        if fingers.count >= 2 {
            beginScroll(fingers)
        } else if let (key, c) = down.first {
            primaryKey = key
            startPoint = point(c)
            lastPoint = startPoint
            mode = .pending
            longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { _ in
                guard mode == .pending else { return }
                post(.rightMouseDown, startPoint, button: .right)
                post(.rightMouseUp, startPoint, button: .right)
                mode = .consumed
            }
        }
    case .pending:
        if fingers.count >= 2 {
            beginScroll(fingers)
        } else if fingers.isEmpty {
            cancelLongPress()
            let p = startPoint
            if Date().timeIntervalSince(lastTapTime) < 0.4,
               hypot(p.x - lastTapPoint.x, p.y - lastTapPoint.y) < 30 {
                clickCount += 1
            } else {
                clickCount = 1
            }
            post(.leftMouseDown, p, clicks: clickCount)
            post(.leftMouseUp, p, clicks: clickCount)
            lastTapTime = Date()
            lastTapPoint = p
            mode = .idle
        } else if let c = contacts[primaryKey], c.tip {
            let p = point(c)
            if hypot(p.x - startPoint.x, p.y - startPoint.y) > dragThreshold {
                cancelLongPress()
                clickCount = 1
                post(.leftMouseDown, startPoint)
                post(.leftMouseDragged, p)
                lastPoint = p
                mode = .dragging
            }
        }
    case .dragging:
        if let c = contacts[primaryKey], c.tip {
            lastPoint = point(c)
            post(.leftMouseDragged, lastPoint)
        } else {
            post(.leftMouseUp, lastPoint)
            mode = fingers.isEmpty ? .idle : .consumed
        }
    case .scrolling:
        if fingers.count >= 2 {
            let c = centroid(fingers)
            let dx = (c.x - scrollCentroid.x) * scrollDirection + scrollRemainder.x
            let dy = (c.y - scrollCentroid.y) * scrollDirection + scrollRemainder.y
            let ix = dx.rounded(.towardZero), iy = dy.rounded(.towardZero)
            scrollRemainder = CGPoint(x: dx - ix, y: dy - iy)
            scrollCentroid = c
            if ix != 0 || iy != 0,
               let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) {
                e.post(tap: .cghidEventTap)
            }
        } else {
            mode = fingers.isEmpty ? .idle : .consumed
        }
    case .consumed:
        if fingers.isEmpty { mode = .idle }
    }
}

let callback: IOHIDValueCallback = { _, _, _, value in
    let el = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(el)
    let usage = IOHIDElementGetUsage(el)
    let v = IOHIDValueGetIntegerValue(value)
    let lo = IOHIDElementGetLogicalMin(el)
    let hi = IOHIDElementGetLogicalMax(el)
    let key = IOHIDElementGetParent(el).map { Int(bitPattern: Unmanaged.passUnretained($0).toOpaque()) } ?? 0

    if probe {
        print(String(format: "page=0x%02x usage=0x%02x value=%d  (range %d...%d) finger=%x",
                     page, usage, v, lo, hi, key & 0xffff))
        return
    }

    var c = contacts[key] ?? Contact()
    switch (page, usage) {
    case (0x01, 0x30):                       // X
        c.x = hi > lo ? min(max(Double(v - lo) / Double(hi - lo), 0), 1) : 0
        contacts[key] = c
    case (0x01, 0x31):                       // Y: last coordinate in a report, so press/drag here
        c.y = hi > lo ? min(max(Double(v - lo) / Double(hi - lo), 0), 1) : 0
        contacts[key] = c
        update()
    case (0x0d, 0x42):                       // Tip Switch
        let was = c.tip
        c.tip = v != 0
        contacts[key] = c
        if was && !c.tip { update() }   // release
    default:
        break
    }
}

if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    print("Requesting Input Monitoring permission (approve the prompt, then re-run if no events arrive)...")
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, callback, nil)

// The controller stays silent until the host sets its Device Mode feature report (ID 7),
// which Windows does automatically. Mode 2 = multi-input.
var touchDevice: IOHIDDevice?
func enableTouchMode() {
    guard let device = touchDevice else { return }
    var report: [UInt8] = [7, 2, 0]
    let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 7, &report, report.count)
    print(r == kIOReturnSuccess ? "Touch enabled." : "Failed to enable touch (0x\(String(r, radix: 16))).")
}
let enableTouch: IOHIDDeviceCallback = { _, _, _, device in
    let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int
    guard page == 0x0d else { return }
    touchDevice = device
    enableTouchMode()
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    // The monitor may have dropped its mode while asleep.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { enableTouchMode() }
}
IOHIDManagerRegisterDeviceMatchingCallback(manager, enableTouch, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("IOHIDManagerOpen failed (0x\(String(openResult, radix: 16))). Grant Input Monitoring to this terminal in System Settings > Privacy & Security.")
    exit(1)
}

if !probe && !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) {
    print("Warning: Accessibility permission not granted; clicks will not be posted. Enable it for this terminal in System Settings > Privacy & Security > Accessibility.")
}
print(probe ? "Probing touch input. Touch the screen (Ctrl-C to stop)..."
            : "Running on display [\(displayIndex)]. Ctrl-C to stop.")
CFRunLoopRun()
