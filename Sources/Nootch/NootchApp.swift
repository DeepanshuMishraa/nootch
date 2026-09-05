import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let openNootchSettings = Notification.Name("Nootch.openSettings")
    static let settingsDidChange = Notification.Name("Nootch.settingsDidChange")
}

@main
struct NootchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store ?? UsageStore())
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Refresh Usage") { appDelegate.store?.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var refreshTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var settingsNotificationObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var helloWorldWindow: NSWindow?
    private(set) var store: UsageStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.configure()
        applyDockVisibility()
        if let iconURL = Bundle.module.url(forResource: "NootchIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.isTemplate = false
            NSApp.applicationIconImage = icon
        }

        settingsNotificationObserver = NotificationCenter.default.addObserver(
            forName: .openNootchSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showHelloWorldWindow()
            }
        }

        settingsChangeObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rebuildSettings = (notification.userInfo?["rebuildSettings"] as? Bool) ?? true
            Task { @MainActor [weak self] in
                self?.panelController?.settingsDidChange()
                guard let self, let window = self.helloWorldWindow else { return }
                window.backgroundColor = self.windowBackgroundColor
                if rebuildSettings {
                    window.contentView = self.makeSettingsContentView()
                }
            }
        }

        let store = UsageStore()
        self.store = store
        store.refresh()
        let controller = NotchPanelController()
        self.panelController = controller
        controller.show(store: store)
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.store?.refresh()
            }
        }
        activityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Poll fast only while an agent is visibly active; idle polling
                // at 5s keeps the /bin/ps + merge cost near zero.
                let active = self?.store?.hasActiveActivity ?? false
                do {
                    try await Task.sleep(for: .seconds(active ? 2 : 5))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.store?.refreshActivity()
            }
        }
        syncLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        activityTask?.cancel()
        if let settingsNotificationObserver {
            NotificationCenter.default.removeObserver(settingsNotificationObserver)
        }
        if let settingsChangeObserver {
            NotificationCenter.default.removeObserver(settingsChangeObserver)
        }
    }

    private func applyDockVisibility() {
        let showInDock = UserDefaults.standard.bool(forKey: AppSettings.showInDockKey)
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private func showHelloWorldWindow() {
        if let helloWorldWindow {
            helloWorldWindow.center()
            helloWorldWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1223, height: 846),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "nootch"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isOpaque = AppSettings.activeWindowStyle == .solid
        window.backgroundColor = windowBackgroundColor
        window.minSize = NSSize(width: 480, height: 320)
        window.contentView = makeSettingsContentView()
        window.setContentSize(NSSize(width: 1223, height: 846))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        helloWorldWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var windowBackgroundColor: NSColor {
        if AppSettings.activeWindowStyle == .solid {
            return AppSettings.currentTheme.solidNSColor
        }
        return AppSettings.currentTheme.nsColor.withAlphaComponent(0.14)
    }

    private func makeSettingsContentView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let content = NSHostingView(rootView: SettingsView(store: store ?? UsageStore()))
        content.translatesAutoresizingMaskIntoConstraints = false

        let background: NSView
        let tintOverlay: NSView?
        let contentSuperview: NSView
        if #available(macOS 26.0, *), AppSettings.activeWindowStyle == .liquidGlass {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.tintColor = AppSettings.currentTheme.nsColor.withAlphaComponent(0.14)
            glass.contentView = content
            background = glass
            tintOverlay = nil
            contentSuperview = glass
        } else if AppSettings.activeWindowStyle == .translucent {
            let translucent = NSVisualEffectView()
            translucent.material = .hudWindow
            translucent.blendingMode = .behindWindow
            translucent.state = .active
            translucent.wantsLayer = true
            translucent.layer?.backgroundColor = AppSettings.currentTheme.nsColor.withAlphaComponent(0.14).cgColor
            background = translucent
            let tint = NSView()
            tint.wantsLayer = true
            tint.layer?.backgroundColor = AppSettings.currentTheme.nsColor.withAlphaComponent(0.16).cgColor
            tintOverlay = tint
            contentSuperview = container
        } else {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = AppSettings.currentTheme.solidNSColor.cgColor
            background = solid
            tintOverlay = nil
            contentSuperview = container
        }

        background.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(background)
        if let tintOverlay {
            tintOverlay.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tintOverlay)
        }
        if #available(macOS 26.0, *), AppSettings.activeWindowStyle == .liquidGlass {
            // NSGlassEffectView owns the hosted content.
        } else {
            container.addSubview(content)
        }

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        if let tintOverlay {
            NSLayoutConstraint.activate([
                tintOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tintOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tintOverlay.topAnchor.constraint(equalTo: container.topAnchor),
                tintOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentSuperview.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentSuperview.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentSuperview.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentSuperview.bottomAnchor),
        ])
        return container
    }

    private func syncLaunchAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let enabled = UserDefaults.standard.object(forKey: AppSettings.launchAtLoginKey) as? Bool ?? true
        do {
            if enabled {
                guard SMAppService.mainApp.status == .notRegistered else { return }
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Could not update launch-at-login: %@", error.localizedDescription)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === helloWorldWindow else { return }
        helloWorldWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @Bindable var store: UsageStore
    @AppStorage(AppSettings.notchPositionKey) private var positionRaw = NotchPosition.right.rawValue
    @AppStorage(AppSettings.notchPositionOffsetKey) private var positionOffset = 0.0
    @AppStorage(AppSettings.themeColorKey) private var themeRaw = ThemeColor.red.rawValue
    @AppStorage(AppSettings.windowStyleKey) private var windowStyleRaw = WindowStyle.liquidGlass.rawValue
    @AppStorage(AppSettings.animationDurationKey) private var animationDuration = 0.32
    @AppStorage(AppSettings.activityAnimationDurationKey) private var activityAnimationDuration = 1.6
    @AppStorage(AppSettings.overlayDisplayModeKey) private var displayModeRaw = OverlayDisplayMode.hover.rawValue
    @AppStorage(AppSettings.usageDisplayModeKey) private var usageDisplayModeRaw = UsageDisplayMode.remaining.rawValue
    @AppStorage(AppSettings.showInDockKey) private var showInDock = false
    @AppStorage(AppSettings.launchAtLoginKey) private var launchAtLogin = true
    @AppStorage(AppSettings.providerIconShapeKey) private var iconShapeRaw = ProviderIconShape.circle.rawValue
    @State private var restartRequired = false
    @State private var launchAtLoginError: String?

    private var currentTheme: ThemeColor {
        ThemeColor(rawValue: themeRaw) ?? .red
    }

    private var usesRainbowTheme: Bool {
        if #available(macOS 26.0, *) {
            return windowStyleRaw == WindowStyle.liquidGlass.rawValue
        }
        return false
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.4"
    }

    private var currentThemeTitle: String {
        currentTheme == .rainbow && !usesRainbowTheme ? "Black" : currentTheme.title
    }

    private var currentThemeDotFill: AnyShapeStyle {
        if currentTheme == .rainbow && usesRainbowTheme {
            return AnyShapeStyle(AngularGradient(
                colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                center: .center
            ))
        } else if currentTheme == .rainbow {
            return AnyShapeStyle(Color.primary.opacity(0.85))
        } else {
            return AnyShapeStyle(currentTheme.color)
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(title: "General") {
                    HStack {
                        Text("Version")
                            .font(.system(size: 13))
                        Spacer()
                        Text(appVersion)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.horizontal, 14)

                    HStack {
                        Text("Show in Dock")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $showInDock)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showInDock) {
                                NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.horizontal, 14)

                    HStack {
                        Text("Launch at login")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin },
                            set: { updateLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                SettingsSection(title: "Position") {
                    HStack {
                        Text("Overlay position")
                            .font(.system(size: 13))
                        Spacer()
                        ElevatedSegmentedPicker(
                            selection: Binding(
                                get: { NotchPosition(rawValue: positionRaw) ?? .right },
                                set: {
                                    positionRaw = $0.rawValue
                                    postSettingsChange()
                                }
                            ),
                            options: NotchPosition.allCases,
                            titleFor: { $0.title },
                            tintColor: currentTheme == .rainbow ? Color(red: 0.08, green: 0.48, blue: 1) : currentTheme.color
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Position offset")
                                .font(.system(size: 13))
                            Spacer()
                            Text(positionOffset == 0 ? "Centered" : String(format: "%+.0f%%", positionOffset * 100))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $positionOffset, in: -1...1, step: 0.01)
                            .tint(currentTheme == .rainbow ? Color.white.opacity(0.85) : currentTheme.color)
                            .onChange(of: positionOffset) {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                postSettingsChange(rebuildSettings: false)
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)

                    HStack {
                        Spacer()
                        Button("Reset") {
                            positionRaw = NotchPosition.right.rawValue
                            positionOffset = 0
                            postSettingsChange(rebuildSettings: false)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(currentTheme == .rainbow ? Color.white.opacity(0.85) : currentTheme.color)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 7)
                }

                SettingsSection(title: "Display") {
                    HStack {
                        Text("Overlay")
                            .font(.system(size: 13))
                        Spacer()
                        ElevatedSegmentedPicker(
                            selection: Binding(
                                get: { OverlayDisplayMode(rawValue: displayModeRaw) ?? .hover },
                                set: {
                                    displayModeRaw = $0.rawValue
                                    postSettingsChange()
                                }
                            ),
                            options: OverlayDisplayMode.allCases,
                            titleFor: { $0.title },
                            tintColor: currentTheme == .rainbow ? Color(red: 0.08, green: 0.48, blue: 1) : currentTheme.color
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }

                SettingsSection(title: "Icon shape") {
                    HStack(spacing: 8) {
                        ForEach(ProviderIconShape.allCases) { shape in
                            ShapePickerOption(
                                shape: shape,
                                isSelected: iconShapeRaw == shape.rawValue,
                                themeColor: currentTheme == .rainbow ? Color(red: 0.08, green: 0.48, blue: 1) : currentTheme.color
                            ) {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                    iconShapeRaw = shape.rawValue
                                    postSettingsChange()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                SettingsSection(title: "Usage") {
                    Picker("Usage display", selection: $usageDisplayModeRaw) {
                        ForEach(UsageDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .onChange(of: usageDisplayModeRaw) {
                        postSettingsChange()
                    }
                }

                SettingsSection(title: "Animation") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Transition speed")
                                .font(.system(size: 13))
                            Spacer()
                            Text(String(format: "%.2fs", animationDuration))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $animationDuration, in: 0.12...0.80)
                            .tint(currentTheme == .rainbow ? Color.white.opacity(0.85) : currentTheme.color)
                            .onChange(of: animationDuration) {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }

                        HStack {
                            Text("Activity indicator speed")
                                .font(.system(size: 13))
                            Spacer()
                            Text(String(format: "%.2fs", activityAnimationDuration))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $activityAnimationDuration, in: 0.4...3.0)
                            .tint(currentTheme == .rainbow ? Color.white.opacity(0.85) : currentTheme.color)
                            .onChange(of: activityAnimationDuration) {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                SettingsSection(title: "Window") {
                    HStack {
                        Text("Window style")
                            .font(.system(size: 13))
                        Spacer()
                        if #available(macOS 26.0, *) {
                            ElevatedMenuPicker(
                                selection: Binding(
                                    get: { WindowStyle(rawValue: windowStyleRaw) ?? .liquidGlass },
                                    set: {
                                        windowStyleRaw = $0.rawValue
                                        restartRequired = true
                                    }
                                ),
                                options: WindowStyle.allCases,
                                titleFor: { $0.title }
                            )
                        } else {
                            ElevatedMenuPicker(
                                selection: Binding(
                                    get: { WindowStyle(rawValue: windowStyleRaw) ?? .translucent },
                                    set: {
                                        windowStyleRaw = $0.rawValue
                                        restartRequired = true
                                    }
                                ),
                                options: [.translucent, .solid],
                                titleFor: { $0.title }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }

                SettingsSection(title: "Colour") {
                    HStack(alignment: .center) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ThemeColor.allCases) { theme in
                                    ThemeSwatch(
                                        theme: theme,
                                        selection: $themeRaw,
                                        usesRainbowTheme: usesRainbowTheme
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                        }

                        Spacer(minLength: 16)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(currentThemeDotFill)
                                .frame(width: 8, height: 8)
                                .shadow(color: currentTheme == .rainbow ? .clear : currentTheme.color.opacity(0.4), radius: 2)

                            Text(currentThemeTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                        .animation(.easeInOut(duration: 0.15), value: themeRaw)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .onChange(of: themeRaw) {
                        postSettingsChange()
                    }
                }

                SettingsSection(title: "Providers") {
                    let supported = ProviderID.supported
                    ForEach(Array(supported.enumerated()), id: \.element.id) { index, provider in
                        let isInstalled = (store.statuses.first { $0.provider == provider }?.detected ?? false)
                            || (provider == .openCode && OpenCodeAdapter.isInstalled)
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ProviderLogo(provider: provider, size: 22)
                                    .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                                Text(provider.name)
                                    .font(.system(size: 13))
                                Spacer()
                                if isInstalled {
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { AppSettings.isProviderEnabled(provider) },
                                            set: { enabled in
                                                UserDefaults.standard.set(enabled, forKey: AppSettings.providerEnabledPrefix + provider.rawValue)
                                                store.refresh()
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                } else {
                                    Text("Not installed")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background {
                                            Capsule()
                                                .fill(Color.white.opacity(0.06))
                                        }
                                        .overlay {
                                            Capsule()
                                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                                        }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .opacity(isInstalled ? 1 : 0.45)

                            if provider == .openCode && isInstalled {
                                let status = store.statuses.first { $0.provider == .openCode }
                                HStack {
                                    Text("Subscription")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(status?.detected == true ? (status?.source ?? "Active") : "Not active")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(status?.detected == true ? .secondary : Color.orange)
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 9)
                            }

                            if index < supported.count - 1 {
                                Divider().opacity(0.25).padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: themeRaw) {
            postSettingsChange()
        }
        .onChange(of: windowStyleRaw) {
            restartRequired = true
        }
        .alert("Launch at login unavailable", isPresented: Binding(
            get: { launchAtLoginError != nil },
            set: { if !$0 { launchAtLoginError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchAtLoginError ?? "macOS could not update the login item.")
        }
        .alert("Restart required", isPresented: $restartRequired) {
            Button("Restart", role: .destructive) {
                restartApplication()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Restart nootch to apply the selected window style.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            launchAtLoginError = "Launch at login is available after installing nootch as an app."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            postSettingsChange()
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    private func postSettingsChange(rebuildSettings: Bool = true) {
        NotificationCenter.default.post(
            name: .settingsDidChange,
            object: nil,
            userInfo: ["rebuildSettings": rebuildSettings])
    }

    private func restartApplication() {
        let applicationURL = Bundle.main.bundleURL
        guard applicationURL.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", applicationURL.path]
        try? launcher.run()
        NSApp.terminate(nil)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
}

private struct ElevatedMenuPicker<T: Hashable & Identifiable>: View {
    let selection: Binding<T>
    let options: [T]
    let titleFor: (T) -> String
    var onChange: (() -> Void)? = nil

    var body: some View {
        Menu {
            ForEach(options) { item in
                Button {
                    selection.wrappedValue = item
                    onChange?()
                } label: {
                    if selection.wrappedValue == item {
                        Label(titleFor(item), systemImage: "checkmark")
                    } else {
                        Text(titleFor(item))
                    }
                }
            }
        } label: {
            Text(titleFor(selection.wrappedValue))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
        }
        .menuStyle(.borderlessButton)
    }
}

private struct ElevatedSegmentedPicker<T: Hashable & Identifiable>: View {
    let selection: Binding<T>
    let options: [T]
    let titleFor: (T) -> String
    var tintColor: Color = .white
    var onChange: (() -> Void)? = nil
    @Namespace private var segmentNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { item in
                let isSelected = selection.wrappedValue == item
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        selection.wrappedValue = item
                        onChange?()
                    }
                } label: {
                    Text(titleFor(item))
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                tintColor.opacity(0.35),
                                                tintColor.opacity(0.18)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 0.75
                                            )
                                    }
                                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "selectedSegment", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.25))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
    }
}

private struct ThemeSwatch: View {
    let theme: ThemeColor
    @Binding var selection: String
    let usesRainbowTheme: Bool
    @State private var isHovered = false

    private var isSelected: Bool { selection == theme.rawValue }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                selection = theme.rawValue
            }
        } label: {
            ZStack {
                // Outer selection ring with subtle gap
                Circle()
                    .strokeBorder(outerRingStyle, lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isSelected ? 1.0 : 0.65)
                    .opacity(isSelected ? 1.0 : 0.0)

                // Swatch color disc
                Circle()
                    .fill(swatchFill)
                    .frame(width: 22, height: 22)
                    .overlay {
                        // Crisp inner highlight rim
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
                    }
                    .overlay {
                        // Subtle edge definition
                        Circle()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(
                        color: shadowColor,
                        radius: isSelected ? 4 : (isHovered ? 3 : 1.5),
                        x: 0,
                        y: isSelected ? 2 : 1
                    )
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .scaleEffect(isHovered && !isSelected ? 1.08 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSelected)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(theme.title)
    }

    private var outerRingStyle: AnyShapeStyle {
        switch theme {
        case .rainbow where usesRainbowTheme:
            AnyShapeStyle(AngularGradient(
                colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                center: .center
            ))
        case .rainbow:
            AnyShapeStyle(Color.primary.opacity(0.8))
        case .gray:
            AnyShapeStyle(Color.primary.opacity(0.65))
        default:
            AnyShapeStyle(theme.color)
        }
    }

    private var swatchFill: AnyShapeStyle {
        switch theme {
        case .rainbow where usesRainbowTheme:
            AnyShapeStyle(AngularGradient(
                colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                center: .center
            ))
        case .rainbow:
            AnyShapeStyle(LinearGradient(
                colors: [Color(white: 0.28), Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        default:
            AnyShapeStyle(theme.color)
        }
    }

    private var shadowColor: Color {
        if theme == .rainbow && usesRainbowTheme {
            return Color.purple.opacity(0.28)
        } else if theme == .rainbow {
            return Color.black.opacity(0.35)
        } else {
            return theme.color.opacity(isSelected ? 0.38 : 0.18)
        }
    }
}

private struct ShapePickerOption: View {
    let shape: ProviderIconShape
    let isSelected: Bool
    let themeColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Live Provider Item preview (Codex with shape gauge ring)
                ZStack {
                    // Shape Track
                    trackView

                    // Quota gauge trim (75% indicator)
                    gaugeTrimView

                    // Codex provider logo in center
                    ProviderLogo(provider: .codex, size: 14)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
                }
                .frame(width: 34, height: 34)

                Text(shape.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.70))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeColor.opacity(0.28),
                                    themeColor.opacity(0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: Color.black.opacity(0.25), radius: 4, y: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(isHovered ? 0.15 : 0.06), lineWidth: 0.75)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var trackView: some View {
        switch shape {
        case .circle:
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3.8)
        case .squircle:
            RoundedRectangle(cornerRadius: 9.5, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 3.8)
        case .rounded:
            RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 3.8)
        case .square:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 3.8)
        }
    }

    @ViewBuilder
    private var gaugeTrimView: some View {
        let accent = isSelected ? themeColor : Color(red: 0.18, green: 0.85, blue: 0.45)
        let strokeStyle = StrokeStyle(lineWidth: 3.8, lineCap: .round)
        switch shape {
        case .circle:
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(accent, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .squircle:
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                .trim(from: 0, to: 0.75)
                .stroke(accent, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .rounded:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .trim(from: 0, to: 0.75)
                .stroke(accent, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .square:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .trim(from: 0, to: 0.75)
                .stroke(accent, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        }
    }
}

