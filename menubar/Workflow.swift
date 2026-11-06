import AppKit
import SwiftUI

// How PitBus works, in one window: the state machine every thing moves through, and what the person and
// Claude do at each step. The picture is drawn here, not shipped as an image, so it follows the appearance.

struct WorkflowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每件事只有三个状态：等你、等外部、已结束").font(.system(size: 17, weight: .semibold))
            Text("面板只展开「等你」。等外部的事不占视野，过了截止或有动静时会带着原因回到「等你」。")
                .font(.system(size: 13)).foregroundColor(.secondary)
            StateMachine().frame(height: 256)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Line(name: "等你", text: "一件事一行，行首是要做的动作（回复、拍板、回应邀请、确认发送、催一下或结束），后面是它回到你手上的原因。")
                Line(name: "等外部", text: "在等别人、等某个 Claude 会话或等某个时间。必带截止，没写就是 2 天；过了截止，或来了新消息而盯它的会话没在监听，就回到等你。")
                Line(name: "新消息", text: "只需要知道、不需要动的消息，看过即可。判错了点「需要我处理」，它会回到等你，并记下来校准分级。")
                Line(name: "交给 Claude", text: "在 Slack 里一条消息开头 @ 自己，或在面板上点「交给 Claude」。答案和回复草稿回到等你，你确认后才发出。")
            }
        }
        .padding(24)
        .frame(width: 720)
    }
}

private struct Line: View {
    let name: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name).font(.system(size: 13, weight: .semibold)).frame(width: 84, alignment: .leading)
            Text(text).font(.system(size: 13)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The control state machine, laid out on a 760-wide grid whose drawing runs from y 56 to 346, scaled to fit.
struct StateMachine: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 760, size.height / 290)
            ctx.translateBy(x: (size.width - 760 * s) / 2, y: (size.height - 290 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: 0, y: -56)
            let edge = Color.secondary.opacity(0.7), accent = Color.accentColor

            func box(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, main: Bool = false) {
                let r = Path(roundedRect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), cornerRadius: 8)
                if main { ctx.fill(r, with: .color(accent.opacity(0.12))) }
                ctx.stroke(r, with: .color(main ? accent : edge), lineWidth: main ? 2 : 1.25)
            }
            func label(_ t: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 11.5, bold: Bool = false,
                       color: Color = .secondary, anchor: UnitPoint = .center) {
                ctx.draw(Text(t).font(.system(size: size, weight: bold ? .semibold : .regular)).foregroundColor(color),
                         at: CGPoint(x: x, y: y), anchor: anchor)
            }
            // a connector through the given points, with a head at the last one
            func arrow(_ pts: [CGPoint], dashed: Bool = false) {
                var p = Path()
                p.addLines(pts)
                ctx.stroke(p, with: .color(edge),
                           style: StrokeStyle(lineWidth: 1.25, dash: dashed ? [4, 3] : []))
                let a = pts[pts.count - 2], b = pts[pts.count - 1]
                let ang = atan2(b.y - a.y, b.x - a.x)
                var head = Path()
                head.move(to: b)
                head.addLine(to: CGPoint(x: b.x - 8 * cos(ang - 0.45), y: b.y - 8 * sin(ang - 0.45)))
                head.addLine(to: CGPoint(x: b.x - 8 * cos(ang + 0.45), y: b.y - 8 * sin(ang + 0.45)))
                head.closeSubpath()
                ctx.fill(head, with: .color(edge))
            }

            arrow([CGPoint(x: 172, y: 144), CGPoint(x: 228, y: 144)])
            arrow([CGPoint(x: 96, y: 180), CGPoint(x: 96, y: 266)])
            arrow([CGPoint(x: 172, y: 304), CGPoint(x: 262, y: 304), CGPoint(x: 262, y: 182)], dashed: true)
            arrow([CGPoint(x: 430, y: 128), CGPoint(x: 518, y: 128)])
            arrow([CGPoint(x: 520, y: 160), CGPoint(x: 432, y: 160)])
            arrow([CGPoint(x: 330, y: 180), CGPoint(x: 330, y: 304), CGPoint(x: 383, y: 304)])
            arrow([CGPoint(x: 620, y: 180), CGPoint(x: 620, y: 304), CGPoint(x: 567, y: 304)])

            box(96, 144, 152, 72)
            label("分拣", 96, 126, size: 15, bold: true, color: .primary)
            label("要不要你动", 96, 148)
            label("拿不准按要处理", 96, 164)
            box(96, 304, 152, 72)
            label("不需要你", 96, 286, size: 15, bold: true, color: .primary)
            label("新消息：看过即可", 96, 308)
            label("噪音：只记日志", 96, 324)
            box(330, 144, 200, 72, main: true)
            label("等你", 330, 126, size: 15, bold: true, color: .primary)
            label("下一步在你手上", 330, 148, color: .primary)
            label("行上写动作和原因", 330, 164, color: .primary)
            box(620, 144, 200, 72)
            label("等外部", 620, 126, size: 15, bold: true, color: .primary)
            label("人 · Claude 会话 · 时间", 620, 148)
            label("必带截止，默认 2 天", 620, 164)
            box(475, 304, 180, 56)
            label("已结束", 475, 294, size: 15, bold: true, color: .primary)
            label("新动静会重新打开", 475, 314)

            label("要处理", 200, 128)
            label("不要", 84, 222, anchor: .trailing)
            label("改判", 250, 230, color: .primary, anchor: .trailing)
            label("你标记 · 对方追问", 250, 246, anchor: .trailing)
            label("你做了动作，等回音", 475, 70)
            label("回复 · 交给 Claude · 稍后提醒", 475, 88)
            label("有动静 · 到点 · 截止已过 · 没人在盯", 475, 200)
            label("回来时写明原因", 475, 216)
            label("做完，或不做", 342, 250, anchor: .leading)
            label("外部办完", 632, 234, anchor: .leading)
            label("审批通过、PR 合并", 632, 250, anchor: .leading)
        }
    }
}

// `PitBus --render-workflow <png> [dark]`: the window drawn offscreen.
func renderWorkflowPreview(to path: String, dark: Bool) {
    let host = NSHostingView(rootView: WorkflowView().background(Color(NSColor.windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.setFrameSize(host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    writePNG(rep, path)
}

