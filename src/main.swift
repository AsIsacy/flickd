import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

// MARK: - Configuration

struct ShortcutSpec: Codable {
    let key: String
    let modifiers: [String]
}

struct AppGestures: Codable {
    let left: ShortcutSpec?
    let right: ShortcutSpec?
    let up: ShortcutSpec?
    let down: ShortcutSpec?

    func shortcut(for direction: SwipeDirection) -> ShortcutSpec? {
        switch direction {
        case .left: return left
        case .right: return right
        case .up: return up
        case .down: return down
        }
    }
}

struct Config: Codable {
    var reverseMouseScroll: Bool = true
    var reverseMouseHorizontalScroll: Bool = false
    var swipeFingers: Int = 3
    var swipeThreshold: Double = 0.05
    var axisDominance: Double = 1.6
    var maxSwipeDuration: Double = 0.75
    var apps: [String: AppGestures] = Config.defaultApps

    static let defaultApps: [String: AppGestures] = {
        let browser = AppGestures(
            left: ShortcutSpec(key: "]", modifiers: ["cmd", "shift"]),
            right: ShortcutSpec(key: "[", modifiers: ["cmd", "shift"]),
            up: ShortcutSpec(key: "t", modifiers: ["cmd"]),
            down: ShortcutSpec(key: "w", modifiers: ["cmd"])
        )
        return [
            "com.google.Chrome": browser,
            "com.apple.Safari": browser,
        ]
    }()

    static let defaultConfig = Config()
}

enum SwipeDirection: String {
    case left, right, up, down
}

struct CompiledShortcut {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let label: String
}

struct CompiledAppGestures {
    let left: CompiledShortcut?
    let right: CompiledShortcut?
    let up: CompiledShortcut?
    let down: CompiledShortcut?

    func shortcut(for dir: SwipeDirection) -> CompiledShortcut? {
        switch dir {
        case .left: return left
        case .right: return right
        case .up: return up
        case .down: return down
        }
    }
}

struct RuntimeConfig {
    let reverseMouseScroll: Bool
    let reverseMouseHorizontalScroll: Bool
    let swipeFingers: Int
    let swipeThreshold: Float
    let axisDominance: Float
    let maxSwipeDuration: Double
    let apps: [String: CompiledAppGestures]
}

// MARK: - Keycode Mapping (US ANSI virtual key codes)

let keyCodeTable: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
    "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
    "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
    "delete": 51, "escape": 53, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

func compileShortcut(_ spec: ShortcutSpec?) -> CompiledShortcut? {
    guard let spec = spec else { return nil }
    guard let code = keyCodeTable[spec.key.lowercased()] else {
        logError("Unknown key name in config: \(spec.key)")
        return nil
    }
    var flags: CGEventFlags = []
    var symbols = ""
    for m in spec.modifiers {
        switch m.lowercased() {
        case "cmd", "command", "⌘":
            flags.insert(.maskCommand)
            symbols += "⌘"
        case "shift", "⇧":
            flags.insert(.maskShift)
            symbols += "⇧"
        case "opt", "option", "alt", "⌥":
            flags.insert(.maskAlternate)
            symbols += "⌥"
        case "ctrl", "control", "⌃":
            flags.insert(.maskControl)
            symbols += "⌃"
        default:
            logError("Unknown modifier in config: \(m)")
        }
    }
    return CompiledShortcut(keyCode: code, flags: flags, label: "\(symbols)\(spec.key.uppercased())")
}

func compileConfig(_ cfg: Config) -> RuntimeConfig {
    var compiledApps: [String: CompiledAppGestures] = [:]
    for (bundleID, g) in cfg.apps {
        compiledApps[bundleID] = CompiledAppGestures(
            left: compileShortcut(g.left),
            right: compileShortcut(g.right),
            up: compileShortcut(g.up),
            down: compileShortcut(g.down)
        )
    }
    return RuntimeConfig(
        reverseMouseScroll: cfg.reverseMouseScroll,
        reverseMouseHorizontalScroll: cfg.reverseMouseHorizontalScroll,
        swipeFingers: max(2, min(5, cfg.swipeFingers)),
        swipeThreshold: Float(cfg.swipeThreshold),
        axisDominance: Float(cfg.axisDominance),
        maxSwipeDuration: cfg.maxSwipeDuration,
        apps: compiledApps
    )
}

// MARK: - Logging

var debugMode = false
var configPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/flickd/config.json")

func logInfo(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    fputs("[\(ts)] [flickd] \(msg)\n", stderr)
    fflush(stderr)
}

func logDebug(_ msg: String) {
    guard debugMode else { return }
    logInfo("DEBUG: \(msg)")
}

func logError(_ msg: String) {
    logInfo("ERROR: \(msg)")
}

// MARK: - MultitouchSupport Dynamic Loader

final class MultitouchBridge {
    typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    typealias RegisterCbFn = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
    typealias UnregisterCbFn = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
    typealias StartFn = @convention(c) (MTDeviceRef, Int32) -> Void
    typealias StopFn = @convention(c) (MTDeviceRef) -> Void
    typealias IsBuiltInFn = @convention(c) (MTDeviceRef) -> Bool
    typealias GetSensorDimsFn = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    private let handle: UnsafeMutableRawPointer
    private let createList: CreateListFn
    private let registerCb: RegisterCbFn
    private let unregisterCb: UnregisterCbFn?
    private let startDev: StartFn
    private let stopDev: StopFn
    private let isBuiltIn: IsBuiltInFn?
    private let getSensorDims: GetSensorDimsFn?

    private var activeDevices: [MTDeviceRef] = []

    init?() {
        precondition(MemoryLayout<MTTouch>.stride == 96, "MTTouch stride mismatch: expected 96, got \(MemoryLayout<MTTouch>.stride)")
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_LAZY) else {
            logError("Failed to dlopen MultitouchSupport.framework")
            return nil
        }
        guard
            let pCreate = dlsym(h, "MTDeviceCreateList"),
            let pReg = dlsym(h, "MTRegisterContactFrameCallback"),
            let pStart = dlsym(h, "MTDeviceStart"),
            let pStop = dlsym(h, "MTDeviceStop")
        else {
            logError("Missing required MultitouchSupport symbols")
            return nil
        }
        self.handle = h
        self.createList = unsafeBitCast(pCreate, to: CreateListFn.self)
        self.registerCb = unsafeBitCast(pReg, to: RegisterCbFn.self)
        self.unregisterCb = dlsym(h, "MTUnregisterContactFrameCallback").map { unsafeBitCast($0, to: UnregisterCbFn.self) }
        self.startDev = unsafeBitCast(pStart, to: StartFn.self)
        self.stopDev = unsafeBitCast(pStop, to: StopFn.self)
        self.isBuiltIn = dlsym(h, "MTDeviceIsBuiltIn").map { unsafeBitCast($0, to: IsBuiltInFn.self) }
        self.getSensorDims = dlsym(h, "MTDeviceGetSensorSurfaceDimensions").map { unsafeBitCast($0, to: GetSensorDimsFn.self) }
    }

    private func isTrackpad(_ dev: MTDeviceRef) -> Bool {
        if let builtInFn = isBuiltIn, builtInFn(dev) {
            return true
        }
        // Distinguish external Magic Trackpad (~160mm wide) from Magic Mouse (~51mm wide)
        if let dimsFn = getSensorDims {
            var w: Int32 = 0
            var h: Int32 = 0
            if dimsFn(dev, &w, &h) == 0 && w > 0 {
                // Dimensions are in hundredths of mm (e.g., ~16000 for trackpad, ~5100 for Magic Mouse)
                let widthMM = w > 1000 ? w / 100 : w
                logDebug("External multitouch device dims: \(w)x\(h) (widthMM≈\(widthMM))")
                return widthMM >= 80
            }
        }
        return true
    }

    func attachAll(callback: MTContactCallbackFunction) {
        detachAll(callback: callback)
        guard let cfArr = createList()?.takeRetainedValue() else {
            logError("MTDeviceCreateList returned nil")
            return
        }
        let count = CFArrayGetCount(cfArr)
        for i in 0..<count {
            guard let rawPtr = CFArrayGetValueAtIndex(cfArr, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: rawPtr)
            guard isTrackpad(dev) else {
                logDebug("Skipping non-trackpad multitouch device \(dev)")
                continue
            }
            _ = Unmanaged<AnyObject>.fromOpaque(dev).retain()
            registerCb(dev, callback)
            startDev(dev, 0)
            activeDevices.append(dev)
        }
        logInfo("Attached to \(activeDevices.count) trackpad device(s)")
    }

    func detachAll(callback: MTContactCallbackFunction) {
        for dev in activeDevices {
            unregisterCb?(dev, callback)
            stopDev(dev)
            Unmanaged<AnyObject>.fromOpaque(dev).release()
        }
        activeDevices.removeAll()
    }
}

// MARK: - Swipe State Machine (Zero-Allocation Hot Path)

struct FingerAnchor {
    var fingerID: Int32 = 0
    var x: Float = 0
    var y: Float = 0
}

final class FlickdEngine {
    static let shared = FlickdEngine()

    private var lock = os_unfair_lock()
    private var runtimeConfig: RuntimeConfig = compileConfig(.defaultConfig)
    private var frontmostBundleID: String = ""
    private var activeAppGestures: CompiledAppGestures? = nil

    // Fixed-size buffers for up to 5 fingers (zero heap allocation in callback!)
    private var tracking = false
    private var triggered = false
    private var lockedOut = false
    private var startTime: Double = 0
    private var anchorCount: Int = 0
    private var anchors = (FingerAnchor(), FingerAnchor(), FingerAnchor(), FingerAnchor(), FingerAnchor())

    private var scrollTap: CFMachPort?
    private var scrollTapSource: CFRunLoopSource?
    private var mtBridge: MultitouchBridge?
    private var tapActive = false
    private var loggedMissingAX = false

    func loadConfig() {
        let fm = FileManager.default
        let dir = (configPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: configPath) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(Config.defaultConfig) {
                try? data.write(to: URL(fileURLWithPath: configPath))
                logInfo("Created default config at \(configPath)")
            }
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let cfg = try JSONDecoder().decode(Config.self, from: data)
            let compiled = compileConfig(cfg)
            os_unfair_lock_lock(&lock)
            runtimeConfig = compiled
            activeAppGestures = compiled.apps[frontmostBundleID]
            os_unfair_lock_unlock(&lock)
            logInfo("Loaded config: reverseMouseScroll=\(compiled.reverseMouseScroll), apps=\(Array(compiled.apps.keys).sorted().joined(separator: ",")), threshold=\(compiled.swipeThreshold)")
        } catch {
            logError("Failed to load config \(configPath): \(error). Using defaults.")
            let compiled = compileConfig(.defaultConfig)
            os_unfair_lock_lock(&lock)
            runtimeConfig = compiled
            activeAppGestures = compiled.apps[frontmostBundleID]
            os_unfair_lock_unlock(&lock)
        }
    }

    func updateFrontmostApp(_ bundleID: String?) {
        let bid = bundleID ?? ""
        os_unfair_lock_lock(&lock)
        frontmostBundleID = bid
        activeAppGestures = runtimeConfig.apps[bid]
        resetSwipeLocked()
        os_unfair_lock_unlock(&lock)
        logDebug("Frontmost app: \(bid) (active=\(activeAppGestures != nil))")
    }

    func resetSwipeState() {
        os_unfair_lock_lock(&lock)
        resetSwipeLocked()
        os_unfair_lock_unlock(&lock)
    }

    @inline(__always)
    private func resetSwipeLocked() {
        tracking = false
        triggered = false
        lockedOut = false
        anchorCount = 0
    }

    @inline(__always)
    private func getAnchor(_ idx: Int) -> FingerAnchor {
        switch idx {
        case 0: return anchors.0
        case 1: return anchors.1
        case 2: return anchors.2
        case 3: return anchors.3
        default: return anchors.4
        }
    }

    @inline(__always)
    private func setAnchor(_ idx: Int, _ val: FingerAnchor) {
        switch idx {
        case 0: anchors.0 = val
        case 1: anchors.1 = val
        case 2: anchors.2 = val
        case 3: anchors.3 = val
        default: anchors.4 = val
        }
    }

    // Called from real-time MultitouchSupport thread (~100 Hz)
    func handleTouchFrame(touches: UnsafeMutablePointer<MTTouch>?, count: Int32, timestamp: Double) {
        os_unfair_lock_lock(&lock)

        guard let appGestures = activeAppGestures else {
            if tracking || triggered || lockedOut {
                resetSwipeLocked()
            }
            os_unfair_lock_unlock(&lock)
            return
        }

        let targetFingers = runtimeConfig.swipeFingers
        let threshold = runtimeConfig.swipeThreshold
        let dominance = runtimeConfig.axisDominance
        let maxDuration = runtimeConfig.maxSwipeDuration

        // Collect active touching fingers (state 3=MakeTouch, 4=Touching)
        var active = (FingerAnchor(), FingerAnchor(), FingerAnchor(), FingerAnchor(), FingerAnchor())
        var activeCount = 0

        if let ptr = touches, count > 0 {
            for i in 0..<Int(count) {
                let t = ptr[i]
                if t.state == Int32(MTTouchStateMakeTouch.rawValue) || t.state == Int32(MTTouchStateTouching.rawValue) {
                    if activeCount < 5 {
                        let fa = FingerAnchor(fingerID: t.fingerID, x: t.normalizedVector.position.x, y: t.normalizedVector.position.y)
                        switch activeCount {
                        case 0: active.0 = fa
                        case 1: active.1 = fa
                        case 2: active.2 = fa
                        case 3: active.3 = fa
                        default: active.4 = fa
                        }
                    }
                    activeCount += 1
                }
            }
        }

        // All fingers lifted -> reset everything
        if activeCount == 0 {
            resetSwipeLocked()
            os_unfair_lock_unlock(&lock)
            return
        }

        // More fingers than target (e.g. 4-finger Spaces/Mission Control) -> lock out until full lift
        if activeCount > targetFingers {
            lockedOut = true
            tracking = false
            os_unfair_lock_unlock(&lock)
            return
        }

        if lockedOut || triggered {
            os_unfair_lock_unlock(&lock)
            return
        }

        // Fewer than target fingers -> pause tracking (don't clear triggered/lockedOut)
        if activeCount < targetFingers {
            tracking = false
            os_unfair_lock_unlock(&lock)
            return
        }

        // Exact targetFingers active!
        if !tracking {
            tracking = true
            startTime = timestamp
            anchorCount = targetFingers
            for i in 0..<targetFingers {
                switch i {
                case 0: setAnchor(0, active.0)
                case 1: setAnchor(1, active.1)
                case 2: setAnchor(2, active.2)
                case 3: setAnchor(3, active.3)
                default: setAnchor(4, active.4)
                }
            }
            os_unfair_lock_unlock(&lock)
            return
        }

        // Check duration window so resting fingers & drifting slowly doesn't trigger
        let elapsed = timestamp - startTime
        if elapsed > maxDuration {
            lockedOut = true
            tracking = false
            os_unfair_lock_unlock(&lock)
            return
        }

        // Match each active finger to its anchor by fingerID and compute coherent displacement
        var sumDx: Float = 0
        var sumDy: Float = 0
        var matched = 0
        var minDx: Float = .greatestFiniteMagnitude
        var maxDx: Float = -.greatestFiniteMagnitude
        var minDy: Float = .greatestFiniteMagnitude
        var maxDy: Float = -.greatestFiniteMagnitude

        for i in 0..<targetFingers {
            let cur: FingerAnchor
            switch i {
            case 0: cur = active.0
            case 1: cur = active.1
            case 2: cur = active.2
            case 3: cur = active.3
            default: cur = active.4
            }
            for j in 0..<anchorCount {
                let anc = getAnchor(j)
                if anc.fingerID == cur.fingerID {
                    let dx = cur.x - anc.x
                    let dy = cur.y - anc.y
                    sumDx += dx
                    sumDy += dy
                    if dx < minDx { minDx = dx }
                    if dx > maxDx { maxDx = dx }
                    if dy < minDy { minDy = dy }
                    if dy > maxDy { maxDy = dy }
                    matched += 1
                    break
                }
            }
        }

        // If finger identities changed mid-gesture, re-anchor cleanly
        if matched != targetFingers {
            startTime = timestamp
            anchorCount = targetFingers
            for i in 0..<targetFingers {
                switch i {
                case 0: setAnchor(0, active.0)
                case 1: setAnchor(1, active.1)
                case 2: setAnchor(2, active.2)
                case 3: setAnchor(3, active.3)
                default: setAnchor(4, active.4)
                }
            }
            os_unfair_lock_unlock(&lock)
            return
        }

        let avgDx = sumDx / Float(targetFingers)
        let avgDy = sumDy / Float(targetFingers)
        let absDx = abs(avgDx)
        let absDy = abs(avgDy)
        let minCoherent = threshold * 0.35

        var detected: SwipeDirection? = nil
        if absDx >= threshold && absDx >= absDy * dominance {
            if avgDx > 0 && minDx >= minCoherent {
                detected = .right
            } else if avgDx < 0 && maxDx <= -minCoherent {
                detected = .left
            }
        } else if absDy >= threshold && absDy >= absDx * dominance {
            if avgDy > 0 && minDy >= minCoherent {
                detected = .up
            } else if avgDy < 0 && maxDy <= -minCoherent {
                detected = .down
            }
        }

        guard let dir = detected else {
            os_unfair_lock_unlock(&lock)
            return
        }

        triggered = true
        let shortcut = appGestures.shortcut(for: dir)
        let appBid = frontmostBundleID
        os_unfair_lock_unlock(&lock)

        if let sc = shortcut {
            DispatchQueue.main.async {
                self.postShortcut(sc)
                logDebug("Swipe \(dir.rawValue) in \(appBid) -> \(sc.label) (dx=\(String(format: "%.3f", avgDx)), dy=\(String(format: "%.3f", avgDy)))")
            }
        }
    }

    private func postShortcut(_ sc: CompiledShortcut) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: sc.keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: sc.keyCode, keyDown: false)
        else { return }
        down.flags = sc.flags
        up.flags = sc.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // Called from CGEventTap for scrollWheel events ONLY
    func handleScrollEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = scrollTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logInfo("Re-enabled scroll CGEventTap after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        // Only reverse discrete scroll wheels (isContinuous == 0 -> external mouse; trackpad/Magic Mouse == 1)
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }

        os_unfair_lock_lock(&lock)
        let revV = runtimeConfig.reverseMouseScroll
        let revH = runtimeConfig.reverseMouseHorizontalScroll
        os_unfair_lock_unlock(&lock)

        if revV {
            // Read all 3 fields BEFORE writing (setting DeltaAxis1 mutates fixed/point fields internally)
            let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            if d1 != 0 || f1 != 0 || p1 != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -d1)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -f1)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -p1)
                logDebug("Reversed mouse vertical scroll: d1=\(d1)->\(-d1)")
            }
        }

        if revH {
            let d2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let f2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let p2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            if d2 != 0 || f2 != 0 || p2 != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -d2)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -f2)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -p2)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    func ensureScrollTap() {
        if let tap = scrollTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        guard AXIsProcessTrusted() else {
            if !loggedMissingAX {
                loggedMissingAX = true
                logInfo("Waiting for Accessibility permission (System Settings -> Privacy & Security -> Accessibility -> Flickd)...")
            }
            return
        }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: nil
        ) else {
            logError("Failed to create CGEventTap even though AXIsProcessTrusted() == true")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.scrollTap = tap
        self.scrollTapSource = source
        self.tapActive = true
        self.loggedMissingAX = false
        logInfo("Accessibility granted! Scroll CGEventTap enabled & active.")
    }

    func start(promptAccessibility: Bool) {
        if promptAccessibility {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        loadConfig()
        updateFrontmostApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)

        // Track frontmost app with zero polling
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            FlickdEngine.shared.updateFrontmostApp(app?.bundleIdentifier)
        }

        // Re-attach trackpads & re-verify event tap after sleep/wake
        wsNC.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            logInfo("System woke from sleep; re-attaching trackpad & verifying scroll tap")
            FlickdEngine.shared.resetSwipeState()
            FlickdEngine.shared.mtBridge?.attachAll(callback: touchFrameCallback)
            FlickdEngine.shared.ensureScrollTap()
        }

        // Attach multitouch trackpad bridge
        mtBridge = MultitouchBridge()
        mtBridge?.attachAll(callback: touchFrameCallback)

        // Start scroll wheel CGEventTap (or poll until Accessibility is granted)
        ensureScrollTap()
        let timer = Timer(timeInterval: 3.0, repeats: true) { _ in
            FlickdEngine.shared.ensureScrollTap()
        }
        RunLoop.main.add(timer, forMode: .common)

        // SIGHUP reloads config without restart
        signal(SIGHUP, SIG_IGN)
        let hupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        hupSource.setEventHandler {
            logInfo("Received SIGHUP; reloading config")
            FlickdEngine.shared.loadConfig()
        }
        hupSource.resume()
        _signalSources.append(hupSource)

        logInfo("flickd started (PID \(ProcessInfo.processInfo.processIdentifier))")
    }

    private var _signalSources: [DispatchSourceSignal] = []
}

// MARK: - C Callbacks

let touchFrameCallback: MTContactCallbackFunction = { _, touches, count, timestamp, _ in
    FlickdEngine.shared.handleTouchFrame(touches: touches, count: count, timestamp: timestamp)
    return 0
}

let scrollTapCallback: CGEventTapCallBack = { proxy, type, event, _ in
    return FlickdEngine.shared.handleScrollEvent(proxy: proxy, type: type, event: event)
}

// MARK: - Main Entrypoint

var promptAX = false
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--debug", "-d":
        debugMode = true
    case "--prompt-accessibility":
        promptAX = true
    case "--config", "-c":
        if let p = args.popFirst() { configPath = p }
    case "--help", "-h":
        print("""
        flickd - Ultra-lightweight macOS 3-finger swipe & mouse scroll-reverser daemon

        Usage: flickd [--debug] [--prompt-accessibility] [--config <path>]
        Config: ~/.config/flickd/config.json (send SIGHUP to reload)
        """)
        exit(0)
    default:
        break
    }
}

// Initialize headless AppKit runtime (.prohibited = zero Dock icon, zero menu bar, minimal RAM)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

FlickdEngine.shared.start(promptAccessibility: promptAX)
app.run()
