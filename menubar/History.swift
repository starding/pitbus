import AppKit
import SwiftUI

// MARK: data — the JSON `pit history` prints

struct HistorySource: Decodable, Identifiable {
    let id: String
    let title: String
    let app: String?
    let count: Int
}

struct HistoryPage: Decodable {
    let items: [Done]
    let total: Int
    let more: Bool
    let sources: [HistorySource]
}

final class HistoryModel: ObservableObject {
    @Published var items: [Done] = []
    @Published var sources: [HistorySource] = []
    @Published var total = 0
    @Published var more = false
    @Published var source: String? = nil
    @Published var query = ""
    let pageSize = 50

    func args(offset: Int) -> [String] {
        var a = ["history", "--offset", "\(offset)", "--limit", "\(pageSize)"]
        if let s = source { a += ["--source", s] }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { a += ["--q", q] }
        return a
    }

    func fetch(offset: Int) -> HistoryPage? {
        let r = Pit.run(args(offset: offset))
        guard r.ok, let d = r.out.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HistoryPage.self, from: d)
    }

    // from the top, after the source or the words changed
    func load() {
        guard let p = fetch(offset: 0) else { return }
        items = p.items
        sources = p.sources
        total = p.total
        more = p.more
    }

    // the next page, when the list is scrolled to its end
    func loadMore() {
        guard more, let p = fetch(offset: items.count) else { return }
        items += p.items
        more = p.more
    }

    var allCount: Int { sources.reduce(0) { $0 + $1.count } }

    // consecutive items of one day, under that day's heading
    var days: [(String, [Done])] {
        var out: [(String, [Done])] = []
        for d in items {
            let day = d.day ?? ""
            if let last = out.last, last.0 == day {
                out[out.count - 1].1.append(d)
            } else {
                out.append((day, [d]))
            }
        }
        return out
    }
}

// MARK: window: sources on the left, the handled things by day on the right

struct HistoryView: View {
    @AppStorage(Look.scaleKey) var textScale = 1.0
    @ObservedObject var model: HistoryModel
    let open: (String?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            HistorySidebar(model: model)
            Divider()
            VStack(spacing: 0) {
                SearchField(text: $model.query, onSubmit: { model.load() })
                    .padding(.horizontal, 20).padding(.vertical, 12)
                Divider()
                list
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(OverlayScrollers())
        .id(textScale)
        .onAppear { model.load() }
    }

    @ViewBuilder var list: some View {
        if model.items.isEmpty {
            Text(model.query.isEmpty ? "还没有处理过的事项" : "没有找到「\(model.query)」")
                .font(Look.font(13)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.days, id: \.0) { day, rows in
                        Text(day).font(Look.font(11, weight: .semibold)).foregroundColor(.secondary)
                            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                        ForEach(rows) { HistoryRow(row: $0, showSource: model.source == nil, open: open) }
                    }
                    if model.more {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(12)
                            .onAppear { model.loadMore() }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}

struct HistorySidebar: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarHeader(text: "来源")
                item(id: nil, title: "全部", count: model.allCount) {
                    Image(systemName: "tray.full").frame(width: 22)
                }
                ForEach(model.sources) { s in
                    item(id: s.id, title: s.title, count: s.count) {
                        SourceIcon(app: s.app, fallback: "antenna.radiowaves.left.and.right")
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 220)
        .background(Color.primary.opacity(0.03))
    }

    func item<Icon: View>(id: String?, title: String, count: Int, @ViewBuilder icon: @escaping () -> Icon) -> some View {
        SidebarItem(selected: model.source == id, action: { model.source = id; model.load() }) {
            icon()
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(Look.font(11)).foregroundColor(.secondary)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("搜索标题和内容", text: $text, onCommit: onSubmit).textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = ""; onSubmit() }) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
        .font(Look.font(13))
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
    }
}

// The panel's handled line, with room for where it came from and the session that followed it.
struct HistoryRow: View {
    let row: Done
    let showSource: Bool
    let open: (String?) -> Void
    @State var hover = false

    var body: some View {
        HStack(spacing: 10) {
            SourceIcon(app: row.app, fallback: "checkmark.circle", size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(Look.font(13)).lineLimit(1)
                Text(meta).font(Look.font(11)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if hover, let s = row.session {
                Button("打开会话") { open(s.link) }.buttonStyle(.borderless).font(Look.font(11))
            }
            Text(row.updated.components(separatedBy: " ").last ?? row.updated)
                .font(Look.font(11)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { open(row.link) }
        .padding(.horizontal, 8)
    }

    var meta: String {
        var parts = [row.state]
        if showSource { parts.append(row.sourceTitle) }
        if let s = row.session { parts.append("「\(s.title)」跟进") }
        return parts.joined(separator: " · ")
    }
}

// `PitBus --render-history <png> [dark] [q=<words>]`: the history window drawn offscreen.
func renderHistoryPreview(to path: String, dark: Bool, query: String?) {
    let model = HistoryModel()
    model.query = query ?? ""
    model.load()
    let host = NSHostingView(rootView: HistoryView(model: model, open: { _ in })
        .background(Color(NSColor.windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 780, height: 560)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    writePNG(rep, path)
}
