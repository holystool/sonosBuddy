import SwiftUI
import AppKit

// MARK: - 可获得键盘焦点的自定义 Panel（支持设置页大模型与端点文本输入框编辑）
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 应用生命周期委托（使用原生 NSStatusItem 避免 MenuBarExtra 窗口自动收起）
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyPanel!
    private var hostingView: NSHostingView<MenuBarView>!
    private var controller: SonosController!
    private var globalClickMonitor: Any?
    private var aboutPanel: KeyPanel!
    private var versionChecker = VersionChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化 controller（必须在 @MainActor 上下文中）
        controller = SonosController()

        // 仅常驻菜单栏，不在 Dock 显示
        NSApp.setActivationPolicy(.accessory)

        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker", accessibilityDescription: "sonosBuddy")
            button.image?.isTemplate = true
            button.action = #selector(handleStatusBarClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 创建 KeyPanel（超紧凑迷你播放控制器，支持文本框聚焦编辑）
        let panelWidth: CGFloat = 260
        let panelHeight: CGFloat = 126
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.hidesOnDeactivate = false

        // 设置 SwiftUI 内容
        let contentView = MenuBarView(controller: controller)
        hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentView = hostingView

        // 观察 controller 播放状态更新菜单栏图标
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusIcon),
            name: NSNotification.Name("SonosPlaybackChanged"),
            object: nil
        )

        // 观察页面切换调整面板尺寸（进入设置/分组展开，返回播放器收拢）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelResize(_:)),
            name: NSNotification.Name("SonosPanelResize"),
            object: nil
        )

        // 应用失去激活状态时自动收回面板（若非设置等常驻页面）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // 观察页面常驻状态（如设置界面时常驻置顶，不自动收回）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSetPinned(_:)),
            name: NSNotification.Name("SonosSetPinned"),
            object: nil
        )

        // 启动时异步检查 GitHub 最新版本
        Task {
            await versionChecker.checkForUpdate()
        }

        // 未授权时自动弹出设置面板，引导用户完成 OAuth 登录
        if controller.config.bearerToken.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showPanel()
                NotificationCenter.default.post(
                    name: NSNotification.Name("SonosOpenSettings"),
                    object: nil
                )
            }
        }
    }

    private var isPinned: Bool = false

    @objc private func handleSetPinned(_ notif: Notification) {
        if let pinned = notif.object as? Bool {
            self.isPinned = pinned
        }
    }

    @objc private func handleAppDidResignActive() {
        if !isPinned {
            hidePanel()
        }
    }

    @objc private func handlePanelResize(_ notif: Notification) {
        guard let size = notif.object as? CGSize else { return }
        var frame = panel.frame
        let diffHeight = size.height - frame.size.height
        frame.origin.y -= diffHeight
        frame.origin.x += (frame.size.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.invalidateShadow()
    }

    @objc private func handleStatusBarClick() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: L(.preferences), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 更新与打赏（有更新时标题带红点提示）
        let aboutTitle = versionChecker.hasUpdate ? "\(L(.aboutAndSupport))  ●" : L(.aboutAndSupport)
        let aboutItem = NSMenuItem(title: aboutTitle, action: #selector(openAboutUpdate), keyEquivalent: "")
        aboutItem.target = self
        if versionChecker.hasUpdate {
            // 红点用橙色高亮
            let attr = NSMutableAttributedString(string: aboutTitle)
            let dotRange = (aboutTitle as NSString).range(of: "●")
            attr.addAttribute(.foregroundColor, value: NSColor.systemRed, range: dotRange)
            aboutItem.attributedTitle = attr
        }
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L(.quitApp), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: NSNotification.Name("SonosOpenSettings"), object: nil)
        if !panel.isVisible {
            showPanel()
        }
    }

    @objc private func openAboutUpdate() {
        if aboutPanel?.isVisible == true {
            hideAboutPanel()
        } else {
            showAboutPanel()
        }
    }

    private func showAboutPanel() {
        if aboutPanel == nil {
            let panelWidth: CGFloat = 340
            let panelHeight: CGFloat = 400
            let p = KeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.titled, .fullSizeContentView, .borderless],
                backing: .buffered,
                defer: false
            )
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .transient]
            p.hidesOnDeactivate = false

            let aboutView = AboutUpdateView(versionChecker: versionChecker) {
                self.hideAboutPanel()
            }
            let hostingView = NSHostingView(rootView: aboutView)
            hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
            p.contentView = hostingView
            aboutPanel = p
        }

        // 定位到菜单栏图标下方
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = aboutPanel.frame.size
        let screenFrame = screen.visibleFrame

        var x = buttonFrame.midX - panelSize.width / 2
        let y = buttonFrame.minY - panelSize.height - 4
        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - panelSize.width - 4))
        aboutPanel.setFrameOrigin(NSPoint(x: x, y: max(screenFrame.minY, y)))
        aboutPanel.invalidateShadow()
        aboutPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideAboutPanel() {
        aboutPanel?.orderOut(nil)
    }

    @objc private func quitApp() {
        stopEventMonitor()
        NSApp.terminate(nil)
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: NSNotification.Name("SonosPanelDidShow"), object: nil)
        startEventMonitor()
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        // 监听全局鼠标按下事件（只会在应用窗口外部发生点击时回调）
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self = self, self.panel.isVisible else { return }
            // 排除对菜单栏状态图标本身的点击（交给图标自身响应）
            if let button = self.statusItem.button, let window = button.window {
                let mouseLocation = NSEvent.mouseLocation
                let buttonScreenRect = window.convertToScreen(button.convert(button.bounds, to: nil))
                if buttonScreenRect.contains(mouseLocation) {
                    return
                }
            }
            Task { @MainActor in
                if !self.isPinned {
                    self.hidePanel()
                }
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func positionPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame

        var x = buttonFrame.midX - panelSize.width / 2
        let y = buttonFrame.minY - panelSize.height - 4

        // 防止超出屏幕边缘
        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - panelSize.width - 4))
        panel.setFrameOrigin(NSPoint(x: x, y: max(screenFrame.minY, y)))
        panel.invalidateShadow()
    }

    @objc private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let isPlaying = controller?.currentGroup?.playbackState.isPlaying == true
        let iconName = isPlaying ? "hifispeaker.fill" : "hifispeaker"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "sonosBuddy")
        button.image?.isTemplate = true
    }

    // 外部调用：关闭面板（由 SettingsView 的"完成"按钮触发）
    func closePanel() {
        hidePanel()
    }
}

// MARK: - 主应用入口
@main
struct SonosBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 使用 Settings 场景占位（真正的 UI 由 AppDelegate 的 NSPanel 管理）
        Settings {
            EmptyView()
        }
    }
}
