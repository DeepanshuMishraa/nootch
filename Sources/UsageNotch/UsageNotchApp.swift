import AppKit
import ServiceManagement
import SwiftUI

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
    private(set) var store: UsageStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        registerLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    private func registerLaunchAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
    }
}

struct SettingsView: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Notch").font(.title2.weight(.semibold))
            Text("Detected providers appear automatically on the right side of the screen.")
                .foregroundStyle(.secondary)
            Divider()
            ForEach(store.detectedStatuses) { status in
                HStack {
                    Image(systemName: status.provider.icon).frame(width: 22)
                    Text(status.provider.name)
                    Spacer()
                    Text(status.detected ? (status.source ?? "Detected") : "Not detected")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Refresh") { store.refresh() }
        }
        .padding(24)
        .frame(width: 380)
    }
}
