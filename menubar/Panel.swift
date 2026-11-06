import AppKit
import SwiftUI

// MARK: data — the JSON `pit status` prints

struct Sess: Decodable {
    let id: String
    let title: String
    let link: String?
    let online: Bool
}

struct Draft: Decodable, Identifiable {
    let id: Int
    let note: String?
    let place: String
    let text: String
    let created: String
    let session: Sess
    let app: String?
    enum CodingKeys: String, CodingKey { case id, note, text, created, session, app, place = "where" }
}

struct Waiting: Decodable, Identifiable {
    let id: Int
    let kind: String
    let place: String
    let note: String?
    let deadline: String?
    let group: String
    let session: Sess
    let app: String?
    enum CodingKeys: String, CodingKey { case id, kind, note, deadline, group, session, app, place = "where" }
}

struct Event: Decodable, Identifiable {
    let id: Int
    let source: String
    let place: String
    let sender: String?
    let recorded: String
    let text: String
    let quote: String?
    let link: String?
    let waitingFor: String?
    let session: Sess?
    let pending: Bool
    let app: String?
    enum CodingKeys: String, CodingKey {
        case id, source, sender, recorded, text, quote, link, session, pending, app, place = "where", waitingFor = "waiting_for"
    }
}

struct Source: Decodable, Identifiable {
    let name: String
    let label: String
    let ok: Int?
    let lastOk: String
    let lastError: String?
    var id: String { name }
    enum CodingKeys: String, CodingKey { case name, label, ok, lastOk = "last_ok", lastError = "last_error" }
}

struct Fresh: Decodable, Identifiable {
    let id: String
    let label: String
    let app: String?
    let interval: Double
    let checked: Double?
    let lastOk: Double?
    let state: String
    let note: String?
    var symbol: String? = nil
    enum CodingKeys: String, CodingKey { case id, label, app, symbol, interval, checked, state, note, lastOk = "last_ok" }
}

struct Sent: Decodable {
    let at: String
    let session: Sess
}

struct Suggest: Decodable {
    let session: Sess
    let reason: String
}

struct Decision: Decodable {
    let label: String
    let p: Double?
    let by: String
}

/// what Claude answered, for a task the person gave it by @-ing themself in Slack
struct Answer: Decodable {
    let status: String
    let text: String?
    let session: String?
    var draft: Int? = nil
}

struct Obj: Decodable, Identifiable {
    let key: String
    let kind: String
    let title: String
    let state: String
    let level: String
    let text: String?
    let link: String?
    let updated: String
    let app: String?
    let session: Sess?
    let agent: String?
    let handed: String?
    let source: String
    let sourceTitle: String
    var unread: Bool? = nil
    var decision: Decision? = nil
    var sent: Sent? = nil
    var action: String? = nil
    var suggest: Suggest? = nil
    var answer: Answer? = nil
    /// "you": it asks something of the person; "them": answered, a session waits for the other side
    var phase: String? = nil
    var reason: String? = nil
    var watch: Watch? = nil
    var keys: [String]? = nil
    /// what the person does about it, when it is theirs: 回复, 拍板, 确认发送…
    var verb: String? = nil
    /// a draft that answers it, waiting for the person's yes
    var draft: Int? = nil
    var id: String { key }
    var waitsOnOthers: Bool { phase == "them" }
    enum CodingKeys: String, CodingKey {
        case key, kind, title, state, level, text, link, updated, app, session, agent, handed, source, unread, decision, sent,
             action, suggest, answer, phase, reason, watch, keys, verb, draft, sourceTitle = "source_title"
    }
    var isSlack: Bool { kind == "slack_dm" || kind == "slack_mention" }
    /// who judged what it asks of me, said only when it was not the plain rule
    var judged: String? {
        guard let d = decision else { return nil }
        if d.by == "person" { return "你标记的" }
        if d.by == "model", let p = d.p { return "模型 \(Int((p * 100).rounded()))%" }
        if d.by == "unsure" { return "模型拿不准，按规则" }
        return nil
    }
    // the text without the state it starts with, which the row already shows in color
    var detail: String? {
        guard var t = text, !t.isEmpty else { return nil }
        if t.hasPrefix(state) { t = String(t.dropFirst(state.count)).trimmingCharacters(in: CharacterSet(charactersIn: "，,；;：: ")) }
        return t.isEmpty ? nil : t
    }
}

struct Done: Decodable, Identifiable {
    let key: String
    let title: String
    let state: String
    let updated: String
    let link: String?
    let app: String?
    let sourceTitle: String
    let session: Sess?
    var day: String? = nil
    var id: String { key }
    enum CodingKeys: String, CodingKey { case key, title, state, updated, link, app, session, day, sourceTitle = "source_title" }
}

/// The session that watches a thing: what it has been told and not taken yet, and its subscriptions on it.
struct Watch: Decodable {
    let session: Sess
    let pending: Int
    let subs: [Int]
}

struct Status: Decodable {
    var drafts: [Draft] = []
    var history: [Done] = []
    var historyToday = 0
    var historyTotal = 0
    var objects: [Obj] = []
    var fyi: [Obj] = []
    var waiting: [Waiting] = []
    var events: [Event] = []
    var sources: [Source] = []
    var freshness: [Fresh] = []
    var pendingSources: [String] = []
    enum CodingKeys: String, CodingKey {
        case drafts, objects, fyi, waiting, events, sources, history, freshness, pendingSources = "pending_sources",
             historyToday = "history_today", historyTotal = "history_total"
    }
}

final class Model: ObservableObject {
    @Published var status = Status()
    @Published var contentHeight: CGFloat = 0
    /// one source picked in the footer: the panel shows only its things until it is picked again
    @Published var only: String? = ProcessInfo.processInfo.environment["PIT_ONLY"]
    var onChange: (() -> Void)?
    var openSettings: (() -> Void)?
    var openHistory: (() -> Void)?
    var openWorkflow: (() -> Void)?

    func reload() {
        let r = Pit.run(["status"])
        if r.ok, let data = r.out.data(using: .utf8), let s = try? JSONDecoder().decode(Status.self, from: data) {
            status = s
        }
        onChange?()
    }

    /// Poll every source now instead of after its interval: the daemon picks it up within seconds,
    /// so the panel reads again once the quick sources and once the slow ones have had time to answer.
    /// One source, by its freshness id ("slack", "src:bob_todo"), or every source when nil.
    func refreshSources(_ id: String? = nil) {
        Pit.run(["refresh"] + (id.map { ["--source", $0.hasPrefix("src:") ? String($0.dropFirst(4)) : $0] } ?? []))
        reload()
        for delay in [4.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reload() }
        }
    }

    func open(_ link: String?) {
        // a command-line session pit started: pit finds it again, in herdr or Terminal
        if let link = link, link.hasPrefix("pit-open:") {
            Pit.run(["open-session", String(link.dropFirst("pit-open:".count))])
            return
        }
        if let link = link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    // Sending speaks for the person: show the whole text and where it goes, and send only on an explicit yes.
    func send(_ d: Draft) {
        let alert = NSAlert()
        alert.messageText = "发送到 \(d.place)？"
        alert.informativeText = d.text
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let r = Pit.run(["draft-send", "\(d.id)"])
        if !r.ok {
            let fail = NSAlert()
            fail.messageText = "发送失败"
            fail.informativeText = r.out
            fail.runModal()
        }
        reload()
    }

    func save(_ d: Draft, text: String) {
        let path = NSTemporaryDirectory() + "pit-draft-\(d.id).txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        Pit.run(["draft-edit", "\(d.id)", "--text-file", path])
        reload()
    }

    // One thing, one session: open the session that follows it, or start one with the thing in its prompt.
    func handoff(_ o: Obj) { handoff(key: o.key) }

    /// something that ended is the person's again, until the next change there
    func reopen(_ key: String) {
        Pit.run(["reopen", key])
        reload()
    }

    /// a group's 日清, opened the way the settings say, with the whole list's prompt every time
    func triage(_ group: String = "mine") {
        let r = Pit.run(["triage", "--group", group])
        guard r.ok else {
            let fail = NSAlert()
            fail.messageText = "没能开始日清"
            fail.informativeText = r.out
            fail.runModal()
            return
        }
        open(r.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func handoff(key: String) {
        let r = Pit.run(["handoff", key])
        guard r.ok else {
            let fail = NSAlert()
            fail.messageText = "没能交给 Agent"
            fail.informativeText = r.out
            fail.runModal()
            return
        }
        open(r.out.trimmingCharacters(in: .whitespacesAndNewlines))
        reload()
    }

    /// the person's word on what a message asks of them; kept to calibrate the model
    func relabel(_ o: Obj, _ label: String, dismiss: Bool = false) {
        Pit.run(["relabel", o.key, label] + (dismiss ? ["--dismiss"] : []))
        reload()
    }

    /// answer a meeting invitation; Google tells the organizer, so it only ever runs on the person's click
    func rsvp(_ o: Obj, _ answer: String) {
        let r = Pit.run(["rsvp", o.key, answer])
        if !r.ok {
            let fail = NSAlert()
            fail.messageText = "没能回复这个会议邀请"
            fail.informativeText = r.out
            fail.runModal()
        }
        reload()
    }

    /// hand it to the session already following the same matter, or say it is not that session's
    func route(_ o: Obj, to s: Sess, reject: Bool = false) {
        Pit.run(["route", o.key, s.id] + (reject ? ["--reject"] : []))
        reload()
    }

    /// stop following a thing: its subscriptions end, and so do the session's wake-ups for it
    func unwatch(_ o: Obj) {
        for id in o.watch?.subs ?? [] { Pit.run(["unwatch", "\(id)"]) }
        reload()
    }

    /// a self-ask run's conversation, continued in Terminal
    func resume(_ o: Obj) {
        Pit.run(["resume", o.key])
    }

    /// handled: the thing is closed — its messages acknowledged, and whatever waited on it stops waiting
    func ack(_ o: Obj) {
        let keys = (o.keys ?? []).isEmpty ? [o.key] : o.keys!
        for k in keys { Pit.run(["ack", k]) }
        for id in o.watch?.subs ?? [] { Pit.run(["unwatch", "\(id)"]) }
        reload()
    }

    func discard(_ d: Draft) {
        Pit.run(["draft-discard", "\(d.id)"])
        reload()
    }
}

// MARK: look — one palette: orange needs you, red is broken, green is fine; the rest is the system's grays

enum Look {
    static let orange = Color(NSColor.systemOrange)
    static let red = Color(NSColor.systemRed)
    static let green = Color(NSColor.systemGreen)
    static let radius: CGFloat = 12

    // 字号：三档，文字、图标和弹窗宽度按同一个倍数放大，标题与正文的比例不变
    static let scaleKey = "textScale"
    static let scales: [(name: String, value: Double)] = [("标准", 1.0), ("大", 1.15), ("特大", 1.3)]
    static var scale: CGFloat { CGFloat(level(UserDefaults.standard.double(forKey: scaleKey))) }
    // 存的值就近落到三档之一；没设过或不认识的值按标准
    static func level(_ v: Double) -> Double {
        scales.map { $0.value }.first { abs($0 - v) < 0.01 } ?? 1
    }
    static var width: CGFloat { (400 * scale).rounded() }
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: (size * scale * 2).rounded() / 2, weight: weight, design: design)
    }
    // ⌘+ / ⌘- 在三档之间移动，⌘0 回到标准
    static func step(_ d: Int) {
        let i = scales.firstIndex { CGFloat($0.value) == scale } ?? 0  // scale 总是三档之一
        let n = d == 0 ? 0 : min(max(i + d, 0), scales.count - 1)
        UserDefaults.standard.set(scales[n].value, forKey: scaleKey)
    }

    // 今天 20:06 → 20:06: today is the default, so it is not said
    static let groupStates: Set<String> = ["等你回复", "待你响应", "待你决定", "等你决定"]

    static func short(_ t: String) -> String { t.hasPrefix("今天 ") ? String(t.dropFirst(3)) : t }
    static var maxBody: CGFloat = 520

    static func symbol(source: String) -> String {
        switch source {
        case "slack": return "bubble.left"
        case "lark_doc": return "text.bubble"
        case "clock": return "clock"
        case "github": return "arrow.triangle.pull"
        case "system": return "desktopcomputer"
        case "gcal": return "calendar"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    static func symbol(object o: Obj) -> String {
        switch o.kind {
        case "github_pr": return "arrow.triangle.pull"
        case "gcal": return "calendar"
        case "pit_sub": return "clock.badge.exclamationmark"
        case "system":
            if o.key.hasSuffix("battery") { return "battery.25" }
            if o.key.hasSuffix("disk") { return "internaldrive" }
            if o.key.hasSuffix("network") { return "wifi.slash" }
            return "desktopcomputer"
        default: return o.level == "alert" ? "exclamationmark.octagon" : "exclamationmark.circle"
        }
    }
}

// The icon of the app a state comes from, in gray: where it came from, without the app's colors competing with status.
enum AppIcons {
    static var cache: [String: NSImage] = [:]

    static func gray(_ bundle: String) -> NSImage? {
        if let hit = cache[bundle] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        guard let tiff = icon.tiffRepresentation, let input = CIImage(data: tiff),
              let f = CIFilter(name: "CIColorControls") else { return nil }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(0.0, forKey: kCIInputSaturationKey)
        f.setValue(1.3, forKey: kCIInputContrastKey)
        f.setValue(-0.06, forKey: kCIInputBrightnessKey)
        guard let out = f.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        cache[bundle] = img
        return img
    }
}

// Where it came from (the app's gray icon, or a symbol when there is no app) plus a dot for its state.
struct SourceIcon: View {
    let app: String?
    let fallback: String
    var badge: Color? = nil
    var size: CGFloat = 20
    var scaled = true  // 弹窗和历史记录跟字号一起放大；设置窗口不放大

    var body: some View {
        let size = self.size * (scaled ? Look.scale : 1)
        return ZStack(alignment: .bottomTrailing) {
            if let a = app, let img = AppIcons.gray(a) {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
            } else {
                Image(systemName: fallback).font(.system(size: size * 0.65)).foregroundColor(.secondary)
                    .frame(width: size - 2, height: size - 2)
            }
            if let b = badge {
                Circle().fill(b).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size + 2, height: size + 2)
    }
}

/// Thin scrollers that show while scrolling and fade, whatever kind of mouse is attached: placed once in a
/// window's view, it gives every AppKit scroll view in that window the overlay style, and keeps it.
struct OverlayScrollers: NSViewRepresentable {
    final class Probe: NSView {
        var watch: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.apply() }
            // macOS switches every scroll view back when a mouse is plugged in or the setting changes
            watch = watch ?? NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.apply() }
        }
        func apply() {
            func walk(_ v: NSView) {
                if let sv = v as? NSScrollView {
                    sv.scrollerStyle = .overlay
                    sv.autohidesScrollers = true
                }
                v.subviews.forEach(walk)
            }
            if let root = window?.contentView { walk(root) }
        }
        deinit { if let w = watch { NotificationCenter.default.removeObserver(w) } }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    // pages and sections bring new scroll views with them
    func updateNSView(_ v: Probe, context: Context) { DispatchQueue.main.async { v.apply() } }
}

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: panel

struct PanelView: View {
    @ObservedObject var model: Model
    @AppStorage(Look.scaleKey) var textScale = 1.0
    @State var showHistory = ProcessInfo.processInfo.environment["PIT_SHOW_HISTORY"] != nil
    @State var showFyi = ProcessInfo.processInfo.environment["PIT_SHOW_FYI"] != nil

    func unreadFyi(_ s: Status) -> Int { s.fyi.filter { $0.unread == true }.count }

    var body: some View {
        let s = model.status
        VStack(spacing: 0) {
            Header(status: s, model: model)
            Divider()
            ScrollView {
                content(s)
                    .background(OverlayScrollers())
                    .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
            }
            .frame(height: min(max(model.contentHeight, 60), Look.maxBody * Look.scale))
            Divider()
            FreshnessList(items: s.freshness.filter { $0.id != "system" }, mine: mineBySource(s), model: model)
        }
        .frame(width: Look.width)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Look.radius, style: .continuous))
        // the hairline edge macOS menus have, so the panel holds its shape on a dark desktop
        .overlay(RoundedRectangle(cornerRadius: Look.radius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .onPreferenceChange(HeightKey.self) { model.contentHeight = $0 }
        .id(textScale)  // 换档后整个面板按新字号重新排版
        .onChange(of: textScale) { _ in DispatchQueue.main.async { (NSApp.delegate as? App)?.fitPanel() } }
    }

    @State var showTheirs = ProcessInfo.processInfo.environment["PIT_OPEN"] != nil  // a preview shows it open


    // The state machine: what is mine, open, most pressing first; what is out, folded until it comes back
    // with a reason; then what asks nothing (new messages) and what is closed.
    @ViewBuilder func content(_ s: Status) -> some View {
        let s = model.only.map { src in s.only(src) } ?? s
        VStack(alignment: .leading, spacing: 0 * Look.scale) {
            if let src = model.only {
                Row(action: { model.only = nil }) {
                    HStack(spacing: 4) {
                        Text("只看 \(model.status.freshness.first { sourceKey($0.id) == src }?.label ?? src)")
                        Spacer()
                        Text("显示全部").foregroundColor(.accentColor)
                    }
                    .font(Look.font(11, weight: .semibold)).foregroundColor(.secondary)
                }
            }
            let mine = s.objects.filter { !$0.waitsOnOthers }
            if mine.isEmpty {
                Label("没有等你的事", systemImage: "checkmark.circle").font(Look.font(13)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                HStack(alignment: .lastTextBaseline) {
                    SectionTitle(text: "等你 \(mine.count)")
                    Spacer()
                    TriageButton(group: "mine", count: mine.count, model: model)
                }
                ForEach(mine) { ObjectRow(obj: $0, model: model) }
            }
            // answered, and a session waits for the other side: out of the way until something happens
            let theirs = s.objects.filter { $0.waitsOnOthers }
            if !theirs.isEmpty {
                HStack(alignment: .lastTextBaseline) {
                    FoldToggle(text: "等外部 \(theirs.count)" + (theirs.first?.reason.map { " · 最近 \($0)" } ?? ""),
                               open: $showTheirs)
                    TriageButton(group: "theirs", count: theirs.count, model: model)
                }
                if showTheirs { ForEach(theirs) { ObjectRow(obj: $0, model: model) } }
            }
            if !s.fyi.isEmpty {
                HStack(alignment: .lastTextBaseline) {
                    FoldToggle(text: "新消息 \(s.fyi.count)" + (unreadFyi(s) > 0 ? " · \(unreadFyi(s)) 条未读" : ""), open: $showFyi)
                    TriageButton(group: "fyi", count: s.fyi.count, model: model)
                }
                if showFyi { ForEach(s.fyi) { FyiRow(obj: $0, model: model) } }
            }
            // what was handled stays reachable, folded away like Reminders' completed items: the last few here,
            // all of it in the history window
            if !s.history.isEmpty {
                HistoryToggle(today: s.historyToday, open: $showHistory)
                if showHistory {
                    ForEach(s.history) { DoneRow(row: $0, model: model) }
                    Row(action: { model.openHistory?() }) {
                        Text(s.historyTotal > s.history.count ? "全部历史（\(s.historyTotal)）…" : "全部历史…")
                            .font(Look.font(12)).foregroundColor(.accentColor).padding(.leading, 22)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// footer ids say `src:<id>` for declared sources; objects say `<id>`
func sourceKey(_ id: String) -> String { id.hasPrefix("src:") ? String(id.dropFirst(4)) : id }

/// how many things wait on the person per source, invitations beyond tomorrow left out as the header does
func mineBySource(_ s: Status) -> [String: Int] {
    var n: [String: Int] = [:]
    for o in s.objects where !o.waitsOnOthers { n[o.source, default: 0] += 1 }
    return n
}

extension Status {
    /// the same status narrowed to one source; sessions keep only what came from it
    func only(_ src: String) -> Status {
        var t = self
        t.objects = objects.filter { $0.source == src }
        t.fyi = fyi.filter { $0.source == src }
        t.drafts = drafts.filter { d in
            (src == "slack" && d.place.hasPrefix("Slack")) || (src == "lark_doc" && d.place.hasPrefix("飞书"))
        }
        t.history = []
        return t
    }
}

// A small square symbol button, the way Notification Center and Linear show row actions on hover.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State var hover = ProcessInfo.processInfo.environment["PIT_HOVER_NAME"] == "1"
    // the panel never becomes key, so system tooltips rarely show: under the pointer the button names itself,
    // and the whole sentence stays as the tooltip for when it does
    var name: String { String(help.split(separator: "：").first ?? Substring(help)) }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(Look.font(11, weight: .semibold))
            if hover { Text(name).font(Look.font(11)).lineLimit(1).fixedSize() }
        }
        .padding(.horizontal, hover ? 7 : 0)
        .frame(minWidth: 24, minHeight: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(hover ? 0.16 : 0.08)))
        .contentShape(Rectangle())
        // it sits inside a row that opens the thing on a tap: its own tap must win over the row's
        .highPriorityGesture(TapGesture().onEnded { action() })
        .help(help).onHover { hover = $0 }
    }
}

struct Header: View {
    let status: Status
    @ObservedObject var model: Model

    var body: some View {
        let s = status
        HStack(spacing: 12) {
            Text("PitBus").font(Look.font(13, weight: .semibold))
            Spacer()
            if !s.pendingSources.isEmpty { Text("\(s.pendingSources.count) 个来源待启用").foregroundColor(Look.orange) }
            MoreMenu(model: model)
        }
        .font(Look.font(12))
        .padding(.horizontal, 16).frame(height: 40)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Look.font(11, weight: .semibold)).foregroundColor(.secondary)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }
}

// A row the whole of which is the main action, highlighted under the pointer like a menu item.
struct Row<Content: View>: View {
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State var hover = false

    var body: some View {
        content()
            .padding(.horizontal, 8).padding(.vertical, 7 * Look.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover && action != nil ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
            .padding(.horizontal, 8)
    }
}

struct Icon: View {
    let name: String
    var color: Color = .secondary
    var body: some View {
        Image(systemName: name).font(Look.font(13)).foregroundColor(color).frame(width: 18 * Look.scale, alignment: .center)
    }
}

// Message text set apart from the panel's own words by a 2px rule, as a quotation.
struct Quoted: View {
    let text: String
    var lines: Int? = 3
    var markdown = false
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 2)
            Text(rich).font(Look.font(12.5)).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
    // Claude's answers come in Markdown; bold and links render, line breaks stay
    var rich: AttributedString {
        markdown ? (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text) : AttributedString(text)
    }
}

struct DraftRow: View {
    let draft: Draft
    @ObservedObject var model: Model

    var body: some View {
        Row(action: nil) {
            HStack(alignment: .top, spacing: 8) {
                SourceIcon(app: draft.app, fallback: "paperplane", badge: Look.orange)
                VStack(alignment: .leading, spacing: 6 * Look.scale) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(draft.note ?? "草稿").font(Look.font(13, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text(draft.created).font(Look.font(11)).foregroundColor(.secondary)
                    }
                    Text("发到 \(draft.place) · \(draft.session.title)").font(Look.font(11)).foregroundColor(.secondary)
                        .lineLimit(1)
                    DraftBody(draft: draft, model: model)
                }
            }
        }
    }
}

/// A draft's text and the person's three answers to it; sending asks once more before it speaks for them.
struct DraftBody: View {
    let draft: Draft
    @ObservedObject var model: Model
    @State var editing = false
    @State var text = ""

    var body: some View {
        Group {
            if editing {
                TextEditor(text: $text).font(Look.font(12.5)).frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Button("保存") { model.save(draft, text: text); editing = false }.keyboardShortcut(.defaultAction)
                    Button("取消") { editing = false }
                }
                .controlSize(.small)
            } else {
                Quoted(text: draft.text, lines: 8)
                HStack(spacing: 8) {
                    Button("发送…") { model.send(draft) }.buttonStyle(.borderedProminent)
                    Button("编辑") { text = draft.text; editing = true }
                    Button("放弃") { model.discard(draft) }
                    Spacer()
                    if draft.session.link != nil {
                        Button("打开会话") { model.open(draft.session.link) }.buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
    }
}

// Two lines, like an inbox: what it is and when; its state and the gist. Actions appear under the pointer.
struct ObjectRow: View {
    let obj: Obj
    @ObservedObject var model: Model
    var inSession = false
    @State var hover = ProcessInfo.processInfo.environment["PIT_HOVER"] != nil  // a preview shows actions

    var body: some View {
        // waiting on others is not the person's move: no color, no badge; what needs a look says so on its own line
        let color = obj.waitsOnOthers ? Color.secondary : (obj.level == "alert" ? Look.red : Look.orange)
        Row(action: obj.link == nil ? nil : { model.open(obj.link) }) {
            HStack(alignment: .top, spacing: 10) {
                // grouped by what it asks, so each row says where it came from
                SourceIcon(app: obj.app, fallback: Look.symbol(object: obj), badge: inSession || obj.waitsOnOthers ? nil : color, size: 16)
                    .padding(.top, 1).help(obj.sourceTitle)
                VStack(alignment: .leading, spacing: 3 * Look.scale) {
                    // under the pointer the actions take the time's place, so a long title ends before them
                    HStack(alignment: .center, spacing: 8) {
                        Text(obj.title).font(Look.font(13, weight: .medium)).lineLimit(1)
                        if obj.unread == true { UnreadDot() }
                        Spacer(minLength: 4)
                        if hover {
                            actions.fixedSize()
                        } else {
                            Text(Look.short(obj.updated)).font(Look.font(11)).foregroundColor(.secondary)
                        }
                    }
                    .frame(minHeight: 20)
                    HStack(spacing: 4) {
                        // what to do about it when it is mine; where it stands when it is out
                        Text(obj.verb ?? obj.state).foregroundColor(color)
                        if !obj.waitsOnOthers, obj.reason == nil, let j = obj.judged { Text(j).foregroundColor(.secondary) }
                        if let r = obj.reason { Text(r).foregroundColor(.secondary).lineLimit(1) }
                        else if let d = obj.detail { Text(d).foregroundColor(.secondary).lineLimit(1) }
                    }
                    .font(Look.font(12)).help(obj.text ?? "")
                    if let w = obj.watch {
                        watching(w).font(Look.font(11)).lineLimit(1)
                    } else if let line = follow {
                        Text(line).font(Look.font(11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    if let id = obj.draft, let d = model.status.drafts.first(where: { $0.id == id }) {
                        DraftBody(draft: d, model: model).padding(.top, 3)
                    }
                    if let a = obj.answer, a.status != "running", let t = a.text {
                        let draft = model.status.drafts.first { $0.id == a.draft }
                        Quoted(text: t, lines: draft == nil ? 12 : 6, markdown: true).padding(.top, 3)
                        if let d = draft {
                            Text("回复草稿 · 发到 \(d.place)").font(Look.font(11)).foregroundColor(.secondary)
                                .padding(.top, 4)
                            DraftBody(draft: d, model: model)
                        }
                        if a.session != nil {
                            Button("继续对话") { model.resume(obj) }.controlSize(.small).buttonStyle(.borderless)
                                .foregroundColor(.secondary).padding(.top, 2)
                        }
                    }
                }
            }
        }
        .onHover { hover = $0 }
    }

    // the session watching it, and what about it needs a look: news it has not read, or no one listening
    func watching(_ w: Watch) -> Text {
        // a session that is not listening matters only once something arrives, and then the row's reason says it
        Text("Claude 在盯 · \(w.session.title)").foregroundColor(.secondary)
    }

    // who follows it, said only when someone does
    var follow: String? {
        if let d = obj.sent { return "\(Look.short(d.at)) 「\(d.session.title)」已代你回复" }
        if inSession { return nil }
        if let g = obj.suggest { return "\(g.reason)，可并入「\(g.session.title)」" }
        if let s = obj.session { return "「\(s.title)」在跟进" }
        if let t = obj.handed, let a = obj.agent { return "\(Look.short(t)) 已交给 \(a)" }
        return nil
    }

    var actions: some View {
        HStack(spacing: 4) {
            if obj.kind == "gcal" && obj.state == "待你响应" {
                IconButton(symbol: "checkmark.circle", help: "接受：会通知发起人") { model.rsvp(obj, "accepted") }
                IconButton(symbol: "questionmark.circle", help: "暂定：会通知发起人") { model.rsvp(obj, "tentative") }
                IconButton(symbol: "xmark.circle", help: "拒绝：会通知发起人") { model.rsvp(obj, "declined") }
                if let g = obj.suggest {
                    IconButton(symbol: "arrow.triangle.merge", help: "并入「\(g.session.title)」：由这个会话跟进") {
                        model.route(obj, to: g.session)
                    }
                }
            } else if obj.kind == "gcal" {
                IconButton(symbol: "checkmark", help: "知道了") { model.ack(obj) }
            } else {
                rowActions
            }
        }
    }

    @ViewBuilder var rowActions: some View {
        HStack(spacing: 4) {
            if let w = obj.watch {
                IconButton(symbol: "arrow.up.forward.app", help: "交给会话：打开「\(w.session.title)」") {
                    model.open(w.session.link)
                }
                if !w.subs.isEmpty {
                    IconButton(symbol: "eye.slash", help: "不跟了：会话不再为这件事被叫醒") { model.unwatch(obj) }
                }
            } else if obj.session != nil {
                IconButton(symbol: "arrow.up.forward.app", help: "打开跟进它的会话") { model.handoff(obj) }
            } else if let g = obj.suggest {
                IconButton(symbol: "arrow.triangle.merge", help: "并入「\(g.session.title)」：由这个会话跟进") {
                    model.route(obj, to: g.session)
                }
                IconButton(symbol: "arrow.uturn.backward", help: "不是这个会话的事：不再建议") {
                    model.route(obj, to: g.session, reject: true)
                }
            } else if obj.answer == nil, let a = obj.agent {
                IconButton(symbol: "sparkles", help: "交给 \(a)：新开会话跟进这件事") { model.handoff(obj) }
            }
            if obj.isSlack {
                IconButton(symbol: "arrow.down.to.line", help: "不用我处理：改为知会，并记下来校准分级") {
                    model.relabel(obj, "fyi", dismiss: true)
                }
            }
            if !obj.waitsOnOthers {
                IconButton(symbol: "checkmark", help: "已处理：这件事结束，不再等，没发的草稿也丢掉；有新消息时重新打开") { model.ack(obj) }
            }
        }
    }
}

struct UnreadDot: View {
    var body: some View { Circle().fill(Color.accentColor).frame(width: 6, height: 6).help("在 Slack 里未读") }
}

/// A section folded by default, opened with its title, as Reminders folds completed items
/// A group's 日清: once it holds enough to be worth sorting at once, one Claude session a day goes through it
/// with the person — what to close, what to do, what it all said
struct TriageButton: View {
    let group: String
    let count: Int
    @ObservedObject var model: Model
    static let help = ["mine": "交给 Claude 梳理等你的事：关掉、拍板、起草或转为等对方，你确认后才动手",
                       "theirs": "交给 Claude 梳理在等的事：哪些有结果了、该催了、要转回你手上",
                       "fyi": "交给 Claude 汇总新消息的要点，找出其实需要你处理的"]
    var body: some View {
        if count >= 5 {
            Button("日清") { model.triage(group) }.buttonStyle(.borderless).font(Look.font(11))
                .foregroundColor(.accentColor).help(Self.help[group] ?? "").padding(.trailing, 16)
        }
    }
}

struct FoldToggle: View {
    let text: String
    @Binding var open: Bool
    var body: some View {
        Button(action: { open.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right").font(Look.font(9, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(text)
                Spacer()
            }
            .font(Look.font(11, weight: .semibold)).foregroundColor(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }
}

/// Something that tells me, asks nothing: one line, a dot while unread, and a way to say it does need me
struct FyiRow: View {
    let obj: Obj
    @ObservedObject var model: Model
    @State var hover = false
    var body: some View {
        Row(action: obj.link == nil ? nil : { model.open(obj.link) }) {
            HStack(spacing: 8) {
                SourceIcon(app: obj.app, fallback: Look.symbol(object: obj), size: 14)
                Text(obj.title).font(Look.font(12)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                if obj.unread == true { UnreadDot() }
                Text(obj.detail ?? "").font(Look.font(12)).foregroundColor(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hover {
                    HStack(spacing: 4) {
                        IconButton(symbol: "arrow.up.to.line", help: "需要我处理：移到等你，并记下来校准分级") {
                            model.relabel(obj, "reply")
                        }
                        IconButton(symbol: "checkmark", help: "看过了") { model.ack(obj) }
                    }
                    .fixedSize()
                } else {
                    Text(Look.short(obj.updated)).font(Look.font(11)).foregroundColor(.secondary).fixedSize()
                }
            }
        }
        .onHover { hover = $0 }
    }
}

struct HistoryToggle: View {
    let today: Int
    @Binding var open: Bool
    var body: some View {
        Button(action: { open.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right").font(Look.font(9, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(today > 0 ? "已结束 · 今天 \(today)" : "已结束")
                Spacer()
            }
            .font(Look.font(11, weight: .semibold)).foregroundColor(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }
}

// One quiet line per handled thing: what it was, how it ended, when.
struct DoneRow: View {
    let row: Done
    @ObservedObject var model: Model
    @State var hover = false
    var body: some View {
        Row(action: row.link == nil ? nil : { model.open(row.link) }) {
            HStack(spacing: 8) {
                SourceIcon(app: row.app, fallback: "checkmark.circle", size: 14).help(row.sourceTitle)
                Text(row.title).font(Look.font(12)).lineLimit(1)
                Spacer(minLength: 4)
                // ended is not final: under the pointer it can come back to the person, or go to Claude
                if hover {
                    HStack(spacing: 4) {
                        IconButton(symbol: "arrow.uturn.left", help: "重新打开：回到等你，直到这里有新动静") {
                            model.reopen(row.key)
                        }
                        IconButton(symbol: "sparkles", help: row.session == nil ? "交给 Claude：新开会话跟进这件事"
                                   : "打开跟进它的会话") { model.handoff(key: row.key) }
                    }
                    .fixedSize()
                } else {
                    // who handled it: a session that answered for the person is named
                    Text((row.session.map { "「\($0.title)」" } ?? "") + "\(row.state) · \(Look.short(row.updated))")
                        .font(Look.font(11)).foregroundColor(.secondary).lineLimit(1).fixedSize()
                }
            }
            .foregroundColor(.secondary)
        }
        .onHover { hover = $0 }
    }
}

struct EventRow: View {
    let event: Event
    @ObservedObject var model: Model
    var inSession = false
    @State var expanded = false

    var body: some View {
        // the row opens the message where it was written; without one, the session that follows it
        Row(action: { model.open(event.link ?? event.session?.link) }) {
            HStack(alignment: .top, spacing: 8) {
                SourceIcon(app: event.app, fallback: Look.symbol(source: event.source), badge: event.pending ? Look.orange : nil)
                VStack(alignment: .leading, spacing: 4 * Look.scale) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(event.sender ?? event.place).font(Look.font(13, weight: .medium)).lineLimit(1)
                        Text(event.place).font(Look.font(11)).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Text(event.recorded).font(Look.font(11)).foregroundColor(.secondary)
                    }
                    if let q = event.quote, !q.isEmpty {
                        Text("评论在「\(q)」").font(Look.font(11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    if !event.text.isEmpty {
                        Quoted(text: event.text, lines: expanded ? nil : 3)
                    }
                    HStack(spacing: 12) {
                        if let w = event.waitingFor {
                            Text(w).font(Look.font(11)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if event.text.count > 120 {
                            Button(expanded ? "收起" : "全文") { expanded.toggle() }
                        }
                        if !inSession, event.link != nil, event.session?.link != nil {
                            Button("打开会话") { model.open(event.session?.link) }
                        }
                    }
                    .buttonStyle(.borderless).font(Look.font(11))
                }
            }
        }
    }
}

struct WaitingRow: View {
    let row: Waiting
    @ObservedObject var model: Model
    var inSession = false

    var body: some View {
        let overdue = row.group == "逾期"
        Row(action: row.session.link == nil ? nil : { model.open(row.session.link) }) {
            HStack(alignment: .top, spacing: 8) {
                SourceIcon(app: row.app, fallback: row.kind == "at" ? "clock" : "hourglass", badge: overdue ? Look.red : nil)
                VStack(alignment: .leading, spacing: 2 * Look.scale) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.note ?? row.place).font(Look.font(13)).lineLimit(1)
                        Spacer()
                        Text(row.deadline.map { overdue ? "已过 \($0)" : "截止 \($0)" } ?? "")
                            .font(Look.font(11)).foregroundColor(overdue ? Look.red : .secondary)
                    }
                    Text(inSession ? "在等 · \(row.place)" : "\(row.place) · \(row.session.title)").font(Look.font(11)).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: freshness

/// 刚刚 / 3 分钟前 / 2 小时前: how long ago, to the unit a person cares about
func ago(_ t: Double, now: Date) -> String {
    let d = max(0, now.timeIntervalSince1970 - t)
    if d < 60 { return "刚刚" }  // seconds would tick on every poll and read as jitter
    if d < 3600 { return "\(Int(d / 60)) 分钟前" }
    return "\(Int(d / 3600)) 小时前"
}

/// 每 1 分钟 / 每 30 秒
func every(_ s: Double) -> String {
    s < 60 ? "每 \(Int(s)) 秒" : (s < 3600 ? "每 \(Int(s / 60)) 分钟" : "每 \(Int(s / 3600)) 小时")
}

/// The sources in one row of dials. Each icon sits in a ring that sweeps like a clock hand from one check to
/// the next, so how fresh a source is and when it looks again read at a glance; a source that fell behind
/// rings orange, one that cannot connect rings red. The count of what waits on the person sits beside it,
/// the details under the pointer.
struct FreshnessList: View {
    let items: [Fresh]
    var mine: [String: Int] = [:]
    @ObservedObject var model: Model
    @State var pointed: String? = ProcessInfo.processInfo.environment["PIT_TIP"]  // a preview can show one
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 2) {
                ForEach(items) { f in item(f, ctx.date) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            // the panel never becomes key, so system tooltips rarely show: the details float above the icon
            .overlayPreferenceValue(IconFrames.self) { frames in
                GeometryReader { g in
                    if let id = pointed, let f = items.first(where: { $0.id == id }), let a = frames[id] {
                        let r = g[a], left = r.midX < g.size.width / 2
                        ZStack(alignment: left ? .bottomLeading : .bottomTrailing) {
                            Color.clear
                            tip(f, ctx.date)
                                .padding(left ? .leading : .trailing, left ? r.minX : g.size.width - r.maxX)
                        }
                        .frame(width: g.size.width, height: 1, alignment: left ? .bottomLeading : .bottomTrailing)
                        .offset(y: r.minY - 4)
                    }
                }
            }
        }
    }

    func tip(_ f: Fresh, _ now: Date) -> some View {
        let n = mine[sourceKey(f.id)] ?? 0
        return VStack(alignment: .leading, spacing: 2 * Look.scale) {
            Text(detail(f, now) + (n > 0 ? " · 等你 \(n) 件" : "")).foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if f.id != "classifier" {
                Text((model.only == sourceKey(f.id) ? "点一下显示全部" : "点一下只看这个来源") + "，右键立即刷新")
                    .foregroundColor(.secondary)
            }
        }
        .font(Look.font(11))
        .frame(width: 236 * Look.scale, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }

    func item(_ f: Fresh, _ now: Date) -> some View {
        let key = sourceKey(f.id)
        let n = mine[key] ?? 0
        let picked = model.only == key
        let idle = f.state == "idle" && !degraded(f)
        return HStack(spacing: 3) {
            Dial(sweep: sweep(f, now), color: ring(f)) {
                SourceIcon(app: f.app, fallback: f.symbol ?? (f.id == "classifier" ? "cpu" : Look.symbol(source: f.id)), size: 12)
            }
            .opacity(idle && f.id != "classifier" ? 0.45 : 1)
            if n > 0 { Text("\(n)").font(Look.font(11, weight: .semibold)).foregroundColor(Look.orange).monospacedDigit() }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(picked ? Color.primary.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        // a source with things on it narrows the panel to them; picked again, everything comes back
        .onTapGesture { if f.id != "classifier" { model.only = picked ? nil : key } }
        .contextMenu {
            if f.id != "classifier" {
                Button("立即刷新\(f.label)") { model.refreshSources(f.id) }
            }
        }
        .onHover { inside in
            if inside { pointed = f.id } else if pointed == f.id { pointed = nil }
        }
        .anchorPreference(key: IconFrames.self, value: .bounds) { [f.id: $0] }
    }

    /// how far the hand has gone from the last check to the next: nil for a source not on a timer
    func sweep(_ f: Fresh, _ now: Date) -> Double? {
        if f.state == "error" || f.state == "late" || degraded(f) { return 1 }
        guard f.state == "ok", let c = f.checked, f.interval > 0 else { return nil }
        return min(1, max(0, (now.timeIntervalSince1970 - c) / f.interval))
    }

    /// red when it cannot connect, orange when it fell behind or the model is missing; quiet when it is fine
    func ring(_ f: Fresh) -> Color {
        switch f.state {
        case "error": return Look.red
        case "late": return Look.orange
        default: return degraded(f) ? Look.orange : Color.secondary.opacity(0.75)
        }
    }

    // a model that should be there and is not; one turned off on purpose is no warning
    func degraded(_ f: Fresh) -> Bool {
        f.id == "classifier" && ((f.note ?? "").hasPrefix("没有模型") || (f.note ?? "").hasPrefix("连不上"))
    }

    func detail(_ f: Fresh, _ now: Date) -> String {
        switch f.state {
        case "error":
            return "\(f.label) · 连不上" + (f.lastOk.map { "，最后成功 \(ago($0, now: now))" } ?? "")
        case "late":
            return "\(f.label) · \(f.checked.map { ago($0, now: now) } ?? "")检查，已落后"
        case "idle", "waiting":
            return "\(f.label) · \(f.note ?? "")"
        default:
            let left = (f.checked ?? 0) + f.interval - now.timeIntervalSince1970
            let next = left <= 0 ? "正在检查" : (left < 60 ? "\(Int(left)) 秒后再查" : "\(Int(left / 60) + 1) 分钟内再查")
            return "\(f.label) · \(f.checked.map { ago($0, now: now) } ?? "")检查，\(next)"
        }
    }
}

/// where each footer icon sits, so its details can float above it
struct IconFrames: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// An icon inside a ring: a faint track and a hand-swept arc, starting at twelve o'clock.
struct Dial<Content: View>: View {
    let sweep: Double?
    let color: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            if let s = sweep {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 1.5)
                Circle().trim(from: 0, to: s)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            content()
        }
        .frame(width: 22, height: 22)
    }
}

/// Settings, history and quit, in the header's corner as macOS panels keep them
struct MoreMenu: View {
    @ObservedObject var model: Model
    var body: some View {
        Menu {
            Button("设置…") { model.openSettings?() }
            Button("历史…") { model.openHistory?() }
            Button("工作方式…") { model.openWorkflow?() }
            Button("立即刷新") { model.refreshSources() }
            Menu("日清") {
                Button("等你…") { model.triage("mine") }
                Button("等外部…") { model.triage("theirs") }
                Button("新消息…") { model.triage("fyi") }
            }
            Divider()
            Text("在任何地方按 ⌃⌥P 打开")
            Divider()
            Button("退出 PitBus") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

// `PitBus --render-panel <png> [dark]`: the panel with the current data, drawn offscreen, to look at it.
func renderPanelPreview(to path: String, dark: Bool) {
    let model = Model()
    model.reload()
    // the whole of it, unscrolled, so the picture shows every section
    if ProcessInfo.processInfo.environment["PIT_TALL"] != nil { Look.maxBody = 4000 }
    let host = NSHostingView(rootView: PanelView(model: model))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Look.width, height: 300), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    // two passes: the first measures the content, the second lays the panel out at that height
    for _ in 0..<2 {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
    }
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    writePNG(rep, path)
}
