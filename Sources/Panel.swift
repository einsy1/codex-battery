import SwiftUI
import AppKit

struct FrostedBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct BatteryBody: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height * 0.23)
    }
}
struct BatteryArtwork: View {
    var fraction: Double
    var tint: Color
    var ready: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var reveal = false
    @State private var sheen = false
    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                BatteryBody().fill(.primary.opacity(0.035))
                BatteryBody().stroke(.primary.opacity(0.16), lineWidth: 1.5)
                GeometryReader { geometry in
                    let width = max(0, (geometry.size.width - 10) * (reveal ? fraction : 0))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: width, height: geometry.size.height - 10)
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(0.4)).frame(height: 1).padding(.horizontal, 8).padding(.top, 1)
                        }
                        .overlay {
                            if !reduceMotion && !reduceTransparency {
                                Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 42).rotationEffect(.degrees(15)).offset(x: sheen ? 165 : -165)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(5)
                }
                if !ready {
                    Image(systemName: "minus").font(.system(size: 23, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .frame(width: 124, height: 58)
            .shadow(color: tint.opacity(reduceTransparency ? 0 : 0.12), radius: 14, y: 5)
            Capsule().fill(.primary.opacity(0.22)).frame(width: 4, height: 19)
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.82).delay(0.08)) { reveal = true }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2).delay(0.35)) { sheen = true }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.85), value: fraction)
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content.background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.06)))
        }
    }
}

struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false
    @State private var showSettings = false
    var body: some View {
        VStack(spacing: 16) {
            header
            if showSettings {
                settingsContent.transition(.opacity)
            } else {
            GlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(store.tint).frame(width: 5, height: 5)
                        Text(store.stale ? (store.loading && store.response == nil ? "正在连接" : "等待更新") : "五小时可用量")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }.padding(.top, 21)
                    BatteryArtwork(fraction: (store.fiveHour?.remaining ?? 0) / 100, tint: store.tint, ready: store.fiveHour != nil)
                        .padding(.top, 22)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(store.fiveHour.map { String(Int($0.remaining.rounded())) } ?? "—")
                            .font(.system(size: 62, weight: .light, design: .rounded)).tracking(-2.5)
                            .contentTransition(.numericText())
                        if store.fiveHour != nil {
                            Text("%").font(.system(size: 25, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: store.fiveHour?.remaining)
                    .padding(.top, 8)
                    Text(store.unavailable && !store.stale ? "当前有额度限制" : store.stale && store.response != nil ? "上次读取的额度" : "留一点余量，给下一个灵感。")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 1)
                    Divider().opacity(0.5).padding(.top, 21).padding(.horizontal, 20)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 7) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 11, weight: .medium))
                            Text(resetText(store.fiveHour?.resetDate, now: context.date))
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            Spacer(minLength: 4)
                            if let date = store.fiveHour?.resetDate {
                                Text(date, style: .time).font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                        }.foregroundStyle(.secondary)
                    }.padding(.horizontal, 20).padding(.vertical, 15)
                }.frame(maxWidth: .infinity)
            }
            weekly
            if let error = store.error {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.circle").padding(.top, 1)
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 3)
            }
            }
            footer
        }
        .padding(20)
        .frame(width: 360)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { FrostedBackdrop() }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 5)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { appeared = true } }
        .alert("设置", isPresented: Binding(get: { store.settingsError != nil }, set: { if !$0 { store.settingsError = nil } })) {
            Button("好", role: .cancel) { store.settingsError = nil }
        } message: { Text(store.settingsError ?? "") }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 17, weight: .medium)).frame(width: 34, height: 34)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Battery").font(.system(size: 14, weight: .semibold))
                Text("灵感，随时就绪").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            if let plan = store.response?.bucket?.planType {
                Text(plan.capitalized).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.primary.opacity(0.045), in: Capsule())
            }
        }.padding(.horizontal, 2)
    }
    private var weekly: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("每周可用量", systemImage: "calendar").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(store.weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.06))
                Capsule().fill(store.stale ? Color.secondary.opacity(0.4) : (store.weekly?.remaining ?? 100) <= 10 ? Color.orange : Color.primary.opacity(0.55))
                    .frame(width: geometry.size.width * (store.weekly?.remaining ?? 0) / 100)
                    .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: store.weekly?.remaining)
            }.frame(height: 4)
            if let date = store.weekly?.resetDate {
                Text("\(date.formatted(.dateTime.month().day().hour().minute())) 重置")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.padding(.horizontal, 6).padding(.vertical, 2)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                HStack(spacing: 5) {
                    Circle().fill(store.stale ? Color.orange.opacity(0.8) : store.tint).frame(width: 4, height: 4)
                    Text(store.loading ? "正在更新…" : freshness(now: context.date)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                    .symbolEffect(.rotate, options: .repeating, isActive: store.loading && !reduceMotion)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(store.loading).help("立即刷新").accessibilityLabel("立即刷新额度")
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "xmark.circle.fill" : "ellipsis.circle")
                    .font(.system(size: 14)).frame(width: 24, height: 26)
                    .contentTransition(.symbolEffect(.replace))
            }.buttonStyle(.plain).help(showSettings ? "返回额度" : "设置").accessibilityLabel(showSettings ? "返回额度" : "设置")

        }.foregroundStyle(.secondary).padding(.top, 1)
    }
    private var preferenceToggles: some View {
        VStack(spacing: 16) {
            HStack {
                Text("菜单栏显示百分比")
                Spacer()
                Toggle("菜单栏显示百分比", isOn: Binding(get: { store.showPercentage }, set: { store.setPercentage($0) })).labelsHidden()
            }
            HStack {
                Text("登录时启动")
                Spacer()
                Toggle("登录时启动", isOn: Binding(get: { store.launchAtLogin }, set: { _ in store.toggleLogin() })).labelsHidden()
            }
        }.toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
    }
    private var iconStylePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("状态栏外观").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(StatusIconStyle.allCases) { style in
                    Button { store.setIconStyle(style) } label: {
                        VStack(spacing: 7) {
                            Image(nsImage: StatusIconRenderer.image(style: style, remaining: 77))
                                .renderingMode(.template).frame(width: 28, height: 22)
                            Text(style.title).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(store.iconStyle == style ? Color.accentColor : Color.primary.opacity(0.7))
                        .background(store.iconStyle == style ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.iconStyle == style ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("状态栏图标：\(style.title)")
                    .accessibilityValue(store.iconStyle == style ? "已选择" : "未选择")
                }
            }
        }
    }
    private var settingsContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("偏好设置").font(.system(size: 18, weight: .semibold))
                iconStylePicker
                preferenceToggles
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Button { store.selectExecutable() } label: { Label("选择 Codex 程序…", systemImage: "folder") }
                    Button { openCodex() } label: { Label("在 Codex 中管理登录", systemImage: "person.crop.circle") }
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text("每 3 分钟自动更新 · 仅查询额度")
                    Text("Codex Battery 1.1 · 独立应用")
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
                Divider()
                HStack {
                    Text("为专注而设计。").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }.controlSize(.small)
                }
            }.padding(22).frame(height: 445)
        }
    }
    private func resetText(_ date: Date?, now: Date) -> String {
        guard let date else { return "等待额度信息" }
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "即将重置" }
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分后重置" : "\(minutes) 分钟后重置"
    }
    private func freshness(now: Date) -> String {
        guard let updated = store.updatedAt else { return "尚未同步" }
        let minutes = max(0, Int(now.timeIntervalSince(updated) / 60))
        return minutes < 1 ? "刚刚更新" : "\(minutes) 分钟前更新"
    }
    private func openCodex() {
        for path in ["/Applications/Codex.app", "/Applications/ChatGPT.app"] where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()); return
        }
    }
}
