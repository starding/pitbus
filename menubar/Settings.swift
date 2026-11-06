import AppKit
import SwiftUI

// MARK: data — the JSON `pit settings` prints: each source with everything about it

struct ScopeRow: Decodable, Identifiable {
    let key: String
    let title: String
    let note: String
    let on: Bool
    var id: String { key }
}

struct SubRow: Decodable, Identifiable {
    let id: Int
    let kind: String
    let note: String?
    let sessionTitle: String
    let deadline: String?
    enum CodingKeys: String, CodingKey { case id, kind, note, deadline, sessionTitle = "session_title" }
}

struct SetRow: Decodable, Identifiable {
    let key: String
    let value: Double
    let `default`: Double
    let meaning: String
    var id: String { key }
}

struct Handler: Decodable {
    let agent: String
    let folder: String
}

struct SrcRow: Decodable, Identifiable {
    let id: String
    let title: String
    let builtin: Bool
    let app: String?
    let status: String
    let interval: Double
    let command: String?
    let addedBy: String?
    let problems: [String?]?
    let ok: Int?
    let lastOk: String?
    let error: String?
    let scopes: [ScopeRow]
    let settings: [SetRow]
    let subs: [SubRow]
    let handler: Handler?
    var icon: String? = nil
    /// a channel from the catalog: what connecting it gives the person, and the company pack it comes from, if any
    var value: String? = nil
    var group: String? = nil
    var org: String? = nil
    var channel: Bool? = nil
    /// switched on and seen working once
    var connected: Bool? = nil
    enum CodingKeys: String, CodingKey {
        case id, title, builtin, app, status, interval, command, problems, ok, error, scopes, settings, subs, handler,
             value, group, org, channel, connected, icon = "symbol", addedBy = "added_by", lastOk = "last_ok"
    }

    var problemList: [String] { (problems ?? []).compactMap { $0 } }
    var symbol: String {
        if let i = icon { return i }
        switch id {
        case "github": return "arrow.triangle.pull"
        case "clock": return "clock"
        default: return "antenna.radiowaves.left.and.right"
        }
    }
    var isConnected: Bool { connected ?? (status == "enabled") }
    /// not connected, and the catalog knows how to connect it
    var connectable: Bool { channel == true && !isConnected }
    // the one color that says how the source is doing
    var statusColor: Color {
        if status == "pending" { return Look.orange }
        if status != "enabled" { return Color.secondary.opacity(0.5) }
        if ok == 0 || !problemList.isEmpty { return Look.red }
        return Look.green
    }
    var statusText: String {
        if status == "pending" { return "待你启用：启用后会在后台定时运行下面的命令" }
        if status != "enabled" { return "已停用" }
        if !problemList.isEmpty { return problemList.joined(separator: "；") }
        if ok == 0 { return error ?? "失败" }
        if let t = lastOk, !t.isEmpty { return "正常 · 上次成功 \(t)" }
        return "正常"
    }
}

struct McpInfo: Decodable { let install: String }

struct SettingsData: Decodable {
    var sources: [SrcRow] = []
    var dataDir: String = ""
    var mcp: McpInfo? = nil
    var claudeOpen: String = "desktop"
    var handleMode: String = "self"
    var handle: HandleLimits? = nil
    enum CodingKeys: String, CodingKey { case sources, mcp, handle, dataDir = "data_dir", claudeOpen = "claude_open", handleMode = "handle_mode" }
    init() {}
}

final class SettingsModel: ObservableObject {
    @Published var data = SettingsData()
    @Published var message: String? = nil
    var onChange: (() -> Void)?

    func reload() {
        let r = Pit.run(["settings"])
        if r.ok, let d = r.out.data(using: .utf8), let s = try? JSONDecoder().decode(SettingsData.self, from: d) {
            data = s
        }
    }

    func run(_ args: [String]) {
        let r = Pit.run(args)
        message = r.ok ? nil : r.out
        reload()
        onChange?()
    }

    func setEnabled(_ s: SrcRow, _ on: Bool) {
        if s.builtin {
            run(["set", "source.\(s.id)", on ? "on" : "off"])
        } else {
            run(["source-set", s.id, "--status", on ? "enabled" : "disabled"])
        }
    }

    /// 「连接」: switched on at once when there is nothing to install, else a Claude session of its own opens
    /// with the install steps
    func connect(_ s: SrcRow) {
        let r = Pit.run(["connect", s.id])
        let out = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        message = r.ok ? nil : out
        if r.ok, out.hasPrefix("claude://") || out.hasPrefix("http"), let url = URL(string: out) {
            NSWorkspace.shared.open(url)
        }
        reload()
        onChange?()
    }

    func test(_ s: SrcRow) {
        let r = Pit.run(["source-test", s.id])
        let a = NSAlert()
        a.messageText = r.ok ? "试运行：\(s.title)" : "试运行失败"
        a.informativeText = String(r.out.prefix(1500))
        a.runModal()
    }

    func remove(_ s: SrcRow) {
        let a = NSAlert()
        a.messageText = "删除来源「\(s.title)」？"
        a.informativeText = "它产生过的事件会保留在日志里。"
        a.addButton(withTitle: "删除")
        a.addButton(withTitle: "取消")
        if a.runModal() == .alertFirstButtonReturn { run(["source-remove", s.id]) }
    }
}

// MARK: window: sources in the sidebar, one page per source

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State var selected = "slack"

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(sources: model.data.sources, selected: $selected, model: model)
            Divider()
            page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 780, height: 540)
        .background(OverlayScrollers())
        .onAppear { model.reload() }
    }

    @ViewBuilder var page: some View {
        let sources = model.data.sources
        if selected == "_connect" {
            ConnectPage(model: model)
        } else if let s = sources.first(where: { $0.id == selected }) ?? sources.first {
            if s.connectable { ChannelPage(source: s, model: model) } else { SourcePage(source: s, model: model) }
        } else {
            Spacer()
        }
    }
}

struct Sidebar: View {
    let sources: [SrcRow]
    @Binding var selected: String

    var model: SettingsModel? = nil

    var body: some View {
        // connected first; then what can still be connected, recommended and company channels last
        let on = sources.filter { $0.isConnected }
        let off = sources.filter { !$0.isConnected }.sorted { ($0.group == nil || $0.group == "builtin" ? 0 : 1) < ($1.group == nil || $1.group == "builtin" ? 0 : 1) }
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarHeader(text: "已连接")
                ForEach(on) { s in SidebarSource(source: s, selected: $selected) }
                if !off.isEmpty {
                    SidebarHeader(text: "可以连接")
                    ForEach(off) { s in SidebarSource(source: s, selected: $selected, model: model) }
                }
                SidebarHeader(text: "PitBus")
                SidebarItem(selected: selected == "_connect", action: { selected = "_connect" }) {
                    Image(systemName: "puzzlepiece.extension").frame(width: 22)
                    Text("接入")
                    Spacer()
                }
            }
            .padding(10)
        }
        .frame(width: 220)
        .background(Color.primary.opacity(0.03))
    }
}

struct SidebarSource: View {
    let source: SrcRow
    @Binding var selected: String
    var model: SettingsModel? = nil
    var body: some View {
        let s = source
        let flagged: Bool = s.status != "enabled" || s.ok == 0
        return SidebarItem(selected: selected == s.id, action: { selected = s.id }) {
            SourceIcon(app: s.app, fallback: s.symbol).opacity(s.isConnected ? 1 : 0.5)
            Text(s.title).lineLimit(1)
            if let org = s.org { Text(org).font(.system(size: 10)).foregroundColor(.secondary) }
            Spacer(minLength: 4)
            if s.connectable, let m = model {
                Button("连接") { m.connect(s) }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundColor(.accentColor)
            } else if flagged {
                Circle().fill(s.statusColor).frame(width: 7, height: 7)
            }
        }
    }
}

struct SidebarHeader: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
    }
}

struct SidebarItem<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 13))
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.primary.opacity(0.09) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

// A group of rows, as System Settings draws them.
struct RowGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            if let f = footer {
                Text(f).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GroupRow<Content: View>: View {
    var last = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) { content() }.padding(.horizontal, 12).padding(.vertical, 9)
            if !last { Divider().padding(.leading, 12) }
        }
    }
}

/// A channel not connected yet: what it gives, and one button that sets it up in the PitBus main session.
struct ChannelPage: View {
    let source: SrcRow
    @ObservedObject var model: SettingsModel
    var body: some View {
        let s = source
        let trying = s.status == "enabled"
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                SourceIcon(app: s.app, fallback: s.symbol).scaleEffect(1.6).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title).font(.system(size: 17, weight: .semibold))
                    Text(trying ? (s.ok == 0 ? (s.error ?? "还没跑通") : "已启用，等第一次跑通")
                         : (s.org.map { "未连接 · \($0)内部系统" } ?? "未连接"))
                        .font(.system(size: 12)).foregroundColor(s.ok == 0 ? Look.red : .secondary).lineLimit(2)
                }
            }
            if let v = s.value { Text(v).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
            VStack(alignment: .leading, spacing: 8) {
                Button(trying ? "继续连接" : "连接") { model.connect(s) }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("新开一个 Claude 会话检查依赖、安装并试运行；需要登录或授权的一步由你自己完成。跑通后这里自动显示「已连接」。")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let m = model.message { Text(m).font(.system(size: 11)).foregroundColor(Look.red) }
            Spacer()
        }
        .padding(24)
    }
}

struct SourcePage: View {
    let source: SrcRow
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if source.command != nil { commandGroup }
                if !source.scopes.isEmpty { scopesGroup }
                subsGroup
                if let h = source.handler { HandlerGroup(source: source, handler: h, model: model) }
                if !source.settings.isEmpty { settingsGroup }
                if let m = model.message { Text(m).font(.system(size: 11)).foregroundColor(Look.red) }
            }
            .padding(24)
        }
    }

    // what it is and how it is doing
    var header: some View {
        let s = source
        let failing = s.ok == 0 || !s.problemList.isEmpty
        return HStack(alignment: .center, spacing: 12) {
            SourceIcon(app: s.app, fallback: s.symbol).scaleEffect(1.6).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(s.statusColor).frame(width: 7, height: 7)
                    Text(s.statusText).font(.system(size: 12)).foregroundColor(failing ? Look.red : Color.secondary).lineLimit(2)
                }
            }
            Spacer()
            if s.id != "clock" {
                if s.status == "pending" {
                    Button("启用") { model.setEnabled(s, true) }.buttonStyle(.borderedProminent).disabled(!s.problemList.isEmpty)
                } else {
                    Toggle("", isOn: Binding(get: { s.status == "enabled" }, set: { model.setEnabled(s, $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    var commandGroup: some View {
        let s = source
        let every = "每 \(Int(s.interval)) 秒运行一次。"
        return RowGroup(title: "命令", footer: s.addedBy == "claude" ? "由 Claude 添加。" + every : every) {
            GroupRow(last: true) {
                Text(s.command ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("试运行") { model.test(s) }
                Button("删除…") { model.remove(s) }
            }
        }
    }

    var scopesGroup: some View {
        let s = source
        return RowGroup(title: "关注范围", footer: "PitBus 默认就会收集这些；需要你看的会出现在面板「需要关注」里。") {
            ForEach(Array(s.scopes.enumerated()), id: \.element.id) { i, sc in
                GroupRow(last: i == s.scopes.count - 1) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sc.title).font(.system(size: 13))
                        Text(sc.note).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { sc.on }, set: { on in
                        model.run(["set", "scope.\(s.id).\(sc.key)", on ? "on" : "off"])
                    })).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    @ViewBuilder var subsGroup: some View {
        let s = source
        let footer = s.subs.isEmpty ? "没有会话在跟进这个来源里的事。会话订阅后，有新消息时会被叫醒。" : "有新消息时，PitBus 叫醒对应的会话。"
        if s.subs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("会话跟进").font(.system(size: 13, weight: .semibold))
                Text(footer).font(.system(size: 11)).foregroundColor(.secondary)
            }
        } else {
        RowGroup(title: "会话跟进", footer: footer) {
            ForEach(Array(s.subs.enumerated()), id: \.element.id) { i, sub in
                GroupRow(last: i == s.subs.count - 1) { SubLine(sub: sub, model: model) }
            }
        }
        }
    }

    var settingsGroup: some View {
        let s = source
        return RowGroup(title: "设置", footer: "改完按回车保存，下一轮检查时生效。") {
            ForEach(Array(s.settings.enumerated()), id: \.element.id) { i, row in
                GroupRow(last: i == s.settings.count - 1) { ThresholdField(row: row, model: model) }
            }
        }
    }
}

// Where this source's things go when handed off from the panel: the agent, and the folder its new sessions start in.
struct HandlerGroup: View {
    let source: SrcRow
    let handler: Handler
    @ObservedObject var model: SettingsModel

    var body: some View {
        let on = handler.agent != "none"
        RowGroup(title: "交给 Agent", footer: on ? "面板里「需要关注」的事项可以一键交给 Claude Code：已有会话在跟进的，打开那个会话；没有的，在下面的文件夹新开一个会话，问题已填好，按回车开始。" : nil) {
            GroupRow(last: !on) {
                Text("处理方式").font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(get: { handler.agent }, set: { model.run(["set", "agent.\(source.id)", $0]) })) {
                    Text("跟随全局设置").tag("claude")
                    Text("手动交给 Claude").tag("manual")
                    Text("不交给 Agent").tag("none")
                }
                .labelsHidden().fixedSize()
            }
            if on {
                GroupRow(last: true) {
                    Text("新会话的文件夹").font(.system(size: 13))
                    Spacer()
                    Text(NSString(string: handler.folder).abbreviatingWithTildeInPath).font(.system(size: 12))
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("选择…") { choose() }
                }
            }
        }
    }

    func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = URL(fileURLWithPath: NSString(string: handler.folder).expandingTildeInPath)
        if p.runModal() == .OK, let url = p.url { model.run(["set", "folder.\(source.id)", url.path]) }
    }
}

struct SubLine: View {
    let sub: SubRow
    @ObservedObject var model: SettingsModel
    var body: some View {
        let meta = [sub.sessionTitle, sub.deadline.map { "截止 \($0)" }].compactMap { $0 }.joined(separator: " · ")
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.note ?? sub.kind).font(.system(size: 13)).lineLimit(1)
                Text(meta).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button("取消跟进") { model.run(["unwatch", "\(sub.id)"]) }.buttonStyle(.borderless)
        }
    }
}

struct ThresholdField: View {
    let row: SetRow
    @ObservedObject var model: SettingsModel
    @State var text = ""

    var body: some View {
        HStack {
            Text(row.meaning).font(.system(size: 13))
            Spacer()
            if row.value != row.default {
                Text("默认 \(fmt(row.default))").font(.system(size: 11)).foregroundColor(.secondary)
            }
            TextField("", text: $text, onCommit: { model.run(["set", row.key, text]) })
                .frame(width: 70).multilineTextAlignment(.trailing)
                .onAppear { text = fmt(row.value) }
        }
    }

    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}

struct HandleLimits: Decodable {
    let handleMaxRunning: Int
    let handleDailyCap: Int
    let handleHours: String
    let handleWeekdays: Bool
    enum CodingKeys: String, CodingKey {
        case handleMaxRunning = "handle_max_running", handleDailyCap = "handle_daily_cap"
        case handleHours = "handle_hours", handleWeekdays = "handle_weekdays"
    }
    /// what an unattended start is held to, in the numbers that apply now
    var text: String {
        "自动处理只写草稿，不会直接发送；同时最多 \(handleMaxRunning) 件，每天最多 \(handleDailyCap) 件，\(handleWeekdays ? "工作日 " : "每天 ")\(handleHours.replacingOccurrences(of: "-", with: ":00–")):00 开始。"
    }
}

enum ClaudeOpen {
    static let handleFooter = [
        "manual": "什么都不自动开始，连 @ 自己的消息也只放进「等你」，由你点「交给 Claude」。",
        "self": "只有你在 Slack 里 @ 自己交代的事，Claude 会自动开始处理。",
        "direct": "另外，Slack 私聊和 @ 你、要你回复或拍板的消息，Claude 也会自动开始处理，把回复写成草稿等你确认。",
        "all": "另外，飞书评论、日历邀请、审批等也会自动处理：这些只给结论和建议，操作仍由你来做。",
    ]
    static let footer = [
        "desktop": "新开会话时指令已经填好，按回车开始；会话里能用桌面版自带的工具。",
        "terminal": "在「终端」里运行 Claude Code，会话直接开始，不用再按回车。",
        "herdr": "在 Ghostty 的 herdr 里运行 Claude Code，会话直接开始；有新消息时 PitBus 直接通知正在等待的会话，不需要会话自己在后台监听。",
    ]
}

struct ConnectPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("接入").font(.system(size: 17, weight: .semibold))
                RowGroup(title: "Claude 何时开始处理", footer: [ClaudeOpen.handleFooter[model.data.handleMode],
                    ["direct", "all"].contains(model.data.handleMode) ? model.data.handle?.text : nil].compactMap { $0 }.joined(separator: "")) {
                    GroupRow(last: true) {
                        Text("新事项来了").font(.system(size: 13))
                        Spacer()
                        Picker("", selection: Binding(get: { model.data.handleMode }, set: { model.run(["set", "handle_mode", $0]) })) {
                            Text("手动").tag("manual")
                            Text("自己 @ 自己时自动").tag("self")
                            Text("私聊和 @ 我自动").tag("direct")
                            Text("全部自动").tag("all")
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                RowGroup(title: "打开 Claude", footer: ClaudeOpen.footer[model.data.claudeOpen]) {
                    GroupRow(last: true) {
                        Text("交给 Claude 时").font(.system(size: 13))
                        Spacer()
                        Picker("", selection: Binding(get: { model.data.claudeOpen }, set: { model.run(["set", "claude_open", $0]) })) {
                            Text("Claude 桌面版").tag("desktop")
                            Text("终端").tag("terminal")
                            Text("Ghostty + herdr").tag("herdr")
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                code("MCP", "Claude 通过 PitBus 的 MCP 服务查看状态、发事件、订阅、写草稿、添加来源。install.sh 已用下面的命令注册到 Claude Code（用户级）。",
                     model.data.mcp?.install ?? "")
                code("CloudEvents", "任何程序都可以按 CloudEvents 1.0 发事件：subject 是对象，data 里放 state、level、title、text、link、app。",
                     "echo '{\"specversion\":\"1.0\",\"id\":\"1\",\"source\":\"ci\",\"type\":\"build\",\"subject\":\"ci:repo/main\",\"data\":{\"state\":\"failed\",\"level\":\"alert\"}}' | pit emit-cloudevent -")
                RowGroup(title: "数据") {
                    GroupRow(last: true) {
                        Text(model.data.dataDir).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                        Spacer()
                        Button("在 Finder 中显示") { NSWorkspace.shared.open(URL(fileURLWithPath: model.data.dataDir)) }
                    }
                }
            }
            .padding(24)
        }
    }

    func code(_ title: String, _ text: String, _ code: String) -> some View {
        RowGroup(title: title, footer: text) {
            GroupRow(last: true) {
                Text(code).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
            }
        }
    }
}

// `PitBus --render-settings <png> [dark] [page=<source id>]`: the settings window drawn offscreen.
func renderSettingsPreview(to path: String, dark: Bool, page: String?) {
    let model = SettingsModel()
    model.reload()
    let host = NSHostingView(rootView: SettingsView(model: model, selected: page ?? "slack")
        .background(Color(NSColor.windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 780, height: 540)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    writePNG(rep, path)
}
