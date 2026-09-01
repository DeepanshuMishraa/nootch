import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let openUsageNotchSettings = Notification.Name("UsageNotch.openSettings")
}

@main
struct UsageNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
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
    private var helloWorldWindow: NSWindow?
    private(set) var store: UsageStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        window.isOpaque = false
        window.backgroundColor = .clear
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

    private func makeSettingsContentView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let content = NSHostingView(rootView: SettingsView())
        content.translatesAutoresizingMaskIntoConstraints = false

        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.contentView = content
            background = glass
        } else {
            let translucent = NSVisualEffectView()
            translucent.material = .hudWindow
            translucent.blendingMode = .behindWindow
            translucent.state = .active
            background = translucent
            container.addSubview(content)
        }

        background.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(background)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let contentSuperview = background as NSView
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
    var body: some View {
        Text("Hell world")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
