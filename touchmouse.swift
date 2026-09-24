// touchmouse: turn any HID touchscreen into mouse input on macOS.
// The touchscreen is found automatically (HID Digitizer page, Touch Screen usage).
//
//   touchmouse --displays           list displays and their indexes
//   touchmouse --probe              print raw HID element values while you touch
//   touchmouse [--display N] [--invert-scroll] [--scroll-speed X]
//       tap = click, double-tap = double-click, drag = drag,
//       hold still 0.6s = right-click, two-finger drag = scroll
//
// Needs Input Monitoring + Accessibility permission for the app running it (Terminal).

import Cocoa
import IOKit.hid

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
//   one finger, move          -> scroll (flick for momentum)
//   one finger, hold, move    -> drag (select text, move windows)
//   one finger, hold, lift    -> right-click
//   two fingers, move         -> scroll
enum Mode { case idle, pending, held, panning, dragging, scrolling, consumed }
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
var panVelocity = CGPoint.zero        // points/second, smoothed
var lastPanTime = Date()
var momentumTimer: Timer?

let dragThreshold = 12.0          // points a finger may wander before a tap becomes a drag
let longPressDelay = 0.6          // seconds
let momentumFriction = 0.95       // velocity kept per 1/60s frame after a flick
let scrollGain: Double = {                 // --scroll-speed X (1.0 = finger speed)
    if let i = args.firstIndex(of: "--scroll-speed"), i + 1 < args.count, let v = Double(args[i + 1]), v > 0 { return v }
    return 0.5
}()
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

func emitScroll(_ dx: Double, _ dy: Double) {
    let ax = dx * scrollGain + scrollRemainder.x, ay = dy * scrollGain + scrollRemainder.y
    let ix = ax.rounded(.towardZero), iy = ay.rounded(.towardZero)
    scrollRemainder = CGPoint(x: ax - ix, y: ay - iy)
    if ix != 0 || iy != 0,
       let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                       wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) {
        e.post(tap: .cghidEventTap)
    }
}

func stopMomentum() { momentumTimer?.invalidate(); momentumTimer = nil }

func startMomentum() {
    stopMomentum()
    guard hypot(panVelocity.x, panVelocity.y) > 150 else { return }
    momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
        panVelocity = CGPoint(x: panVelocity.x * momentumFriction, y: panVelocity.y * momentumFriction)
        if hypot(panVelocity.x, panVelocity.y) < 20 { t.invalidate(); momentumTimer = nil; return }
        emitScroll(panVelocity.x / 60, panVelocity.y / 60)
    }
}

func beginPan() {
    cancelLongPress()
    stopMomentum()
    mode = .panning
    scrollRemainder = .zero
    panVelocity = .zero
    lastPanTime = Date()
    lastPoint = startPoint
    post(.mouseMoved, startPoint)         // scroll events go to whatever is under the cursor
}

func beginScroll(_ fingers: [Contact]) {
    cancelLongPress()
    mode = .scrolling
    scrollCentroid = centroid(fingers)
    scrollRemainder = .zero
    post(.mouseMoved, scrollCentroid)     // scroll events go to whatever is under the cursor
}

func panStep(_ p: CGPoint) {
    let dx = (p.x - lastPoint.x) * scrollDirection, dy = (p.y - lastPoint.y) * scrollDirection
    let now = Date(), dt = now.timeIntervalSince(lastPanTime)
    if dt > 0.001 {
        panVelocity = CGPoint(x: 0.6 * dx / dt + 0.4 * panVelocity.x, y: 0.6 * dy / dt + 0.4 * panVelocity.y)
        lastPanTime = now
    }
    lastPoint = p
    emitScroll(dx, dy)
}

func update() {
    let down = contacts.filter { $0.value.tip }
    let fingers = down.map(\.value)
    if !fingers.isEmpty { stopMomentum() }

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
                mode = .held
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
                clickCount = 1
                beginPan()
                panStep(p)
            }
        }
    case .held:
        if fingers.count >= 2 {
            beginScroll(fingers)
        } else if fingers.isEmpty {
            post(.rightMouseDown, startPoint, button: .right)
            post(.rightMouseUp, startPoint, button: .right)
            mode = .idle
        } else if let c = contacts[primaryKey], c.tip {
            let p = point(c)
            if hypot(p.x - startPoint.x, p.y - startPoint.y) > dragThreshold {
                clickCount = 1
                post(.leftMouseDown, startPoint)
                post(.leftMouseDragged, p)
                lastPoint = p
                mode = .dragging
            }
        }
    case .panning:
        if fingers.count >= 2 {
            beginScroll(fingers)
        } else if let c = contacts[primaryKey], c.tip {
            panStep(point(c))
        } else {
            if Date().timeIntervalSince(lastPanTime) > 0.08 { panVelocity = .zero }
            startMomentum()
            mode = fingers.isEmpty ? .idle : .consumed
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
            emitScroll((c.x - scrollCentroid.x) * scrollDirection, (c.y - scrollCentroid.y) * scrollDirection)
            scrollCentroid = c
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
IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0x0d, kIOHIDDeviceUsageKey: 0x04] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, callback, nil)

// Many controllers stay silent until the host sets the Device Mode feature (0x0D/0x52)
// to 2 = multi-input, which Windows does automatically.
var touchDevices: [IOHIDDevice] = []
func describe(_ device: IOHIDDevice) -> String {
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "touchscreen"
    let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    return "\(name) (\(String(format: "%04x:%04x", vid, pid)))"
}
func enableTouchMode(_ device: IOHIDDevice) {
    let match = [kIOHIDElementUsagePageKey: 0x0d, kIOHIDElementUsageKey: 0x52] as CFDictionary
    let modes = (IOHIDDeviceCopyMatchingElements(device, match, 0) as? [IOHIDElement] ?? [])
        .filter { IOHIDElementGetType($0) == kIOHIDElementTypeFeature }
    guard !modes.isEmpty else {
        print("\(describe(device)): no Device Mode feature, assuming touch is already on.")
        return
    }
    for el in modes {
        let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, 0, 2)
        let r = IOHIDDeviceSetValue(device, el, value)
        print(r == kIOReturnSuccess ? "\(describe(device)): touch enabled."
                                    : "\(describe(device)): failed to enable touch (0x\(String(r, radix: 16))).")
    }
}
let deviceAdded: IOHIDDeviceCallback = { _, _, _, device in
    touchDevices.append(device)
    enableTouchMode(device)
}
let deviceRemoved: IOHIDDeviceCallback = { _, _, _, device in
    touchDevices.removeAll { $0 == device }
    print("\(describe(device)): disconnected.")
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    // The monitor may have dropped its mode while asleep.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { touchDevices.forEach(enableTouchMode) }
}
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAdded, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("IOHIDManagerOpen failed (0x\(String(openResult, radix: 16))). Grant Input Monitoring to this terminal in System Settings > Privacy & Security.")
    exit(1)
}

if !probe && !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) {
    print("Warning: Accessibility permission not granted; clicks will not be posted. Enable it for this terminal in System Settings > Privacy & Security > Accessibility.")
}
if (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).isEmpty { print("No touchscreen found yet; waiting for one to be connected...") }
print(probe ? "Probing touch input. Touch the screen (Ctrl-C to stop)..."
            : "Running on display [\(displayIndex)]. Ctrl-C to stop.")
CFRunLoopRun()
