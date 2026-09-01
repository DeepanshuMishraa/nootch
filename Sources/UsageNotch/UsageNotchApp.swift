import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let openUsageNotchSettings = Notification.Name("UsageNotch.openSettings")
    static let settingsDidChange = Notification.Name("UsageNotch.settingsDidChange")
}

@main
struct UsageNotchApp: App {
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
        NSApp.setActivationPolicy(.accessory)
        settingsNotificationObserver = NotificationCenter.default.addObserver(
            forName: .openUsageNotchSettings,
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
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panelController?.settingsDidChange()
                if let self, let window = self.helloWorldWindow {
                    window.backgroundColor = self.windowBackgroundColor
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
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.store?.refreshActivity()
            }
        }
        registerLaunchAtLogin()
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
        window.title = "Usage Notch"
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

    private func registerLaunchAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
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
    @AppStorage(AppSettings.themeColorKey) private var themeRaw = ThemeColor.red.rawValue
    @AppStorage(AppSettings.windowStyleKey) private var windowStyleRaw = WindowStyle.liquidGlass.rawValue
    @State private var providerRevision = 0
    @State private var restartRequired = false

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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
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

                    Divider().opacity(0.25).padding(.horizontal, 12)

                    HStack {
                        Text("Notch position")
                            .font(.system(size: 13))
                        Spacer()
                        ElevatedMenuPicker(
                            selection: Binding(
                                get: { NotchPosition(rawValue: positionRaw) ?? .right },
                                set: { positionRaw = $0.rawValue }
                            ),
                            options: NotchPosition.allCases,
                            titleFor: { $0.title },
                            onChange: { postSettingsChange() }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
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
                }

                SettingsSection(title: "Providers") {
                    let supported = ProviderID.supported
                    ForEach(Array(supported.enumerated()), id: \.element.id) { index, provider in
                        let isInstalled = store.statuses.first { $0.provider == provider }?.detected ?? false
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
                                                providerRevision &+= 1
                                                postSettingsChange()
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
        .alert("Restart required", isPresented: $restartRequired) {
            Button("Restart", role: .destructive) {
                restartApplication()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Restart Usage Notch to apply the selected window style.")
        }
        .id(providerRevision)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func postSettingsChange() {
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
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

