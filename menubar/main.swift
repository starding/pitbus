// PitBus: the menu bar face of pit. It reads `pit status` and calls `pit draft-send`,
// `pit draft-edit`, `pit draft-discard`; everything else lives in the daemon. Swift 5.6+, macOS 12+.
import AppKit
import Carbon
import Combine
import SwiftUI

let dataDir = NSString(string: "~/Library/Application Support/pit").expandingTildeInPath

struct Pit {
    // python and pit.py paths are written to config.json by install.sh
    static func command() -> [String] {
        let url = URL(fileURLWithPath: dataDir + "/config.json")
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let py = cfg["python"] as? String, let script = cfg["pit_py"] as? String {
            return [py, script]
        }
        return ["/usr/bin/python3", NSString(string: "~/Documents/pit/pit/pit.py").expandingTildeInPath]
    }

    @discardableResult
    static func run(_ args: [String]) -> (ok: Bool, out: String) {
        let cmd = command() + args
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd[0])
        p.arguments = Array(cmd.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}

// An opaque panel with the system's rounded corners and shadow; it can take keys so a draft can be edited.
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }

    // ⌘+ / ⌘= 放大，⌘- 缩小，⌘0 恢复标准，和浏览器、Slack 一样
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .numericPad, .function])
        if mods == .command, let c = e.charactersIgnoringModifiers {
            switch c {
            case "+", "=": Look.step(1); return true
            case "-": Look.step(-1); return true
            case "0": Look.step(0); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: e)
    }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let model = Model()
    let notifier = Notifier()
    var panel: Panel!
    var host: NSHostingController<PanelView>!
    var hotKey: EventHotKeyRef?
    var timer: Timer?
    var sizeWatch: AnyCancellable?
    let settingsModel = SettingsModel()
    var settingsWindow: NSWindow?
    let historyModel = HistoryModel()
    var historyWindow: NSWindow?
    var workflowWindow: NSWindow?

    func showWorkflow() {
        panel.orderOut(nil)
        if workflowWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "PitBus 工作方式"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: WorkflowView())
            w.center()
            workflowWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        workflowWindow?.makeKeyAndOrderFront(nil)
    }

    func showHistory() {
        panel.orderOut(nil)
        if historyWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "PitBus 历史"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: HistoryView(model: historyModel, open: { [weak self] in
                self?.model.open($0)
            }))
            w.center()
            historyWindow = w
        }
        historyModel.load()
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        panel.orderOut(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "PitBus 设置"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(model: settingsModel))
            w.center()
            settingsWindow = w
        }
        settingsModel.reload()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.image = pitIcon()
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // keeps the place the person ⌘-drags it to
        item.autosaveName = "dev.pit.menubar.item"
        makePanel()
        model.openSettings = { [weak self] in self?.showSettings() }
        model.openHistory = { [weak self] in self?.showHistory() }
        model.openWorkflow = { [weak self] in self?.showWorkflow() }
        settingsModel.onChange = { [weak self] in self?.model.reload() }
        model.onChange = { [weak self] in self?.updateBadge() }
        // the panel is as tall as what it shows, up to a limit; it grows and shrinks from its top edge
        sizeWatch = model.$contentHeight.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitPanel() }
        }
        registerHotKey()
        notifier.open = { [weak self] link in self?.model.open(link) }
        notifier.start()
        model.reload()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.model.reloadInBackground() }
    }

    func makePanel() {
        // borderless: the SwiftUI view draws the rounded shape, the window only casts its shadow
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: Look.width, height: 300),
                      styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        host = NSHostingController(rootView: PanelView(model: model))
        panel.contentViewController = host
    }

    func fitPanel() {
        guard panel.isVisible else { return }
        let size = host.view.fittingSize
        var f = panel.frame
        f.origin.y = f.maxY - size.height
        f.origin.x = f.midX - size.width / 2  // 换字号时宽度变了，保持居中
        if let vf = panel.screen?.visibleFrame { f.origin.x = min(max(f.origin.x, vf.minX + 8), vf.maxX - size.width - 8) }
        f.size = size
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
    }

    // Clicking anywhere else closes it, like a menu.
    func windowDidResignKey(_ notification: Notification) {
        if NSApp.modalWindow == nil { panel.orderOut(nil) }
    }

    // A solid point and the number next to it mean things that need the person:
    // drafts waiting for confirmation and objects at attention or alert.
    func updateBadge() {
        let n = model.status.drafts.count + model.status.objects.count + model.status.pendingSources.count
        item.button?.image = pitIcon(filled: n > 0)
        item.button?.title = n > 0 ? " \(n)" : ""
    }

    // Left or right click, the icon only opens the panel: everything else lives in it.
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel(underIcon: true) }
    }

    // A crowded menu bar hides status items, so the panel has two more ways in:
    // the ⌃⌥P hot key, and opening PitBus again (Spotlight, `open -a PitBus`). Those open it at the pointer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(underIcon: false)
        return false
    }

    func showPanel(underIcon: Bool) {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        model.reloadInBackground()  // the panel opens on what the last tick read; the fresh read follows
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        var anchor = NSEvent.mouseLocation
        if underIcon, let w = item.button?.window {
            anchor = NSPoint(x: w.frame.midX, y: w.frame.minY - 4)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height)
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? App)?.showPanel(underIcon: false) }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5049_5420), id: 1)  // 'PIT '
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-app-icon"), i + 1 < args.count {
    renderAppIconSet(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
    renderIconPreview(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
    _ = NSApplication.shared
    renderSettingsPreview(to: args[i + 1], dark: args.contains("dark"),
                          page: args.first { $0.hasPrefix("page=") }.map { String($0.dropFirst(5)) })
    exit(0)
}
if let i = args.firstIndex(of: "--render-history"), i + 1 < args.count {
    _ = NSApplication.shared
    renderHistoryPreview(to: args[i + 1], dark: args.contains("dark"),
                         query: args.first { $0.hasPrefix("q=") }.map { String($0.dropFirst(2)) })
    exit(0)
}
if let i = args.firstIndex(of: "--render-workflow"), i + 1 < args.count {
    _ = NSApplication.shared
    renderWorkflowPreview(to: args[i + 1], dark: args.contains("dark"))
    exit(0)
}
if let i = args.firstIndex(of: "--render-panel"), i + 1 < args.count {
    _ = NSApplication.shared
    renderPanelPreview(to: args[i + 1], dark: args.contains("dark"))
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
