import AppKit
import Observation
import SwiftUI

// MARK: - Shapes

/// Smooth Apple-style curved notch with true concave entry scoops and convex shoulders.
struct RightEdgeNotchShape: Shape {
    var flareWidth: CGFloat = 24
    var flareHeight: CGFloat = 36
    var cornerRadius: CGFloat = 28

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(flareWidth, AnimatablePair(flareHeight, cornerRadius))
        }
        set {
            flareWidth = newValue.first
            flareHeight = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let fh = min(flareHeight, h * 0.35)
        let cr = min(cornerRadius, max(2, (h - 2 * fh) * 0.5))
        let fw = min(flareWidth, max(2, w * 0.45))
        let k: CGFloat = 0.5522847

        // 1. Start at top-right on the screen boundary
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))

        // 2. Top-right concave scoop from (maxX, minY) to (maxX - fw, minY + fh)
        path.addCurve(
            to: CGPoint(x: rect.maxX - fw, y: rect.minY + fh),
            control1: CGPoint(x: rect.maxX, y: rect.minY + fh * k),
            control2: CGPoint(x: rect.maxX - fw * (1 - k), y: rect.minY + fh)
        )

        // 3. Top horizontal straight bridge
        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.minY + fh))

        // 4. Top-left convex rounded shoulder
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + fh + cr),
            control1: CGPoint(x: rect.minX + cr * (1 - k), y: rect.minY + fh),
            control2: CGPoint(x: rect.minX, y: rect.minY + fh + cr * (1 - k))
        )

        // 5. Left straight vertical boundary
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - fh - cr))

        // 6. Bottom-left convex rounded shoulder
        path.addCurve(
            to: CGPoint(x: rect.minX + cr, y: rect.maxY - fh),
            control1: CGPoint(x: rect.minX, y: rect.maxY - fh - cr * (1 - k)),
            control2: CGPoint(x: rect.minX + cr * (1 - k), y: rect.maxY - fh)
        )

        // 7. Bottom horizontal straight bridge
        path.addLine(to: CGPoint(x: rect.maxX - fw, y: rect.maxY - fh))

        // 8. Bottom-right concave scoop from (maxX - fw, maxY - fh) to (maxX, maxY)
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - fw * (1 - k), y: rect.maxY - fh),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - fh * k)
        )

        // 9. Close along screen boundary
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

/// Popover card with an animatable triangular callout beak pointing at the hovered item.
struct PopoverCalloutShape: Shape {
    var pointerY: CGFloat
    var cornerRadius: CGFloat = 16
    var pointerWidth: CGFloat = 10
    var pointerHeight: CGFloat = 18

    var animatableData: CGFloat {
        get { pointerY }
        set { pointerY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let pw = pointerWidth
        let ph = pointerHeight / 2

        let cardRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width - pw, height: rect.height)
        let clampedPointerY = min(max(pointerY, cardRect.minY + r + ph), cardRect.maxY - r - ph)

        // Top-left
        path.move(to: CGPoint(x: cardRect.minX + r, y: cardRect.minY))

        // Top edge
        path.addLine(to: CGPoint(x: cardRect.maxX - r, y: cardRect.minY))
        path.addArc(
            center: CGPoint(x: cardRect.maxX - r, y: cardRect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge down to pointer beak top
        path.addLine(to: CGPoint(x: cardRect.maxX, y: clampedPointerY - ph))
        // Pointer beak tip
        path.addLine(to: CGPoint(x: cardRect.maxX + pw, y: clampedPointerY))
        // Pointer beak bottom
        path.addLine(to: CGPoint(x: cardRect.maxX, y: clampedPointerY + ph))

        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.maxY - r))
        path.addArc(
            center: CGPoint(x: cardRect.maxX - r, y: cardRect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: cardRect.minX + r, y: cardRect.maxY))
        path.addArc(
            center: CGPoint(x: cardRect.minX + r, y: cardRect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge up to top-left corner
        path.addLine(to: CGPoint(x: cardRect.minX, y: cardRect.minY + r))
        path.addArc(
            center: CGPoint(x: cardRect.minX + r, y: cardRect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Hosting & Panel

final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onExit: (() -> Void)?
    private var panelTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let panelTrackingArea {
            removeTrackingArea(panelTrackingArea)
        }
        let panelTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(panelTrackingArea)
        self.panelTrackingArea = panelTrackingArea
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onExit?()
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
    }

    func place() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let panelWidth: CGFloat = 440
        let panelHeight: CGFloat = 480
        let x = frame.maxX - panelWidth
        // Shift position up right below top menu bar
        let y = max(frame.minY + 20, frame.maxY - panelHeight - 12)
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}

@MainActor
@Observable
final class NotchInteractionState {
    var isHovered = false
    var pinnedOpen = false
    var isDetailVisible = false
    var isSettingsHovered = false
    var providerCount = 0
    var hoveredIndex: Int?
    var collapseToken = 0
    var panelFrame: NSRect = .zero
}

@MainActor
final class NotchPanelController {
    let panel = NotchPanel()
    private let interaction = NotchInteractionState()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func show(store: UsageStore) {
        panel.place()
        interaction.panelFrame = panel.frame

        let hostedView = TrackingHostingView(rootView: NotchView(
            store: store,
            interaction: interaction
        ))

        hostedView.onExit = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interaction.isHovered = false
                self.interaction.isSettingsHovered = false
                self.interaction.hoveredIndex = nil
                self.interaction.collapseToken &+= 1
            }
        }
        panel.contentView = hostedView
        panel.orderFrontRegardless()

        setupClickOutsideMonitors()
    }

    private func setupClickOutsideMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.collapseFromOutsideClick()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let mouseScreen = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                if !self.interactionRegion.contains(mouseScreen) {
                    self.collapseFromOutsideClick()
                }
            }
            return event
        }

        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMove(event)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMove(event)
            }
            return event
        }
    }

    private func handleMouseMove(_ event: NSEvent) {
        let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let frame = panel.frame
        interaction.panelFrame = frame

        let isInside = interactionRegion.contains(location)
        guard isInside else {
            if interaction.isHovered || interaction.pinnedOpen {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    interaction.isHovered = false
                    interaction.pinnedOpen = false
                    interaction.isDetailVisible = false
                    interaction.isSettingsHovered = false
                    interaction.hoveredIndex = nil
                    interaction.collapseToken &+= 1
                }
            }
            return
        }

        if !interaction.isHovered {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                interaction.isHovered = true
            }
        }

        let topOffset = frame.maxY - location.y
        let count = interaction.providerCount
        let railBottom = CGFloat(count) * 88 + 48

        // Check if mouse is hovering in the bottom flare of the notch
        let isOverBottomFlare = (location.x >= (frame.maxX - 110)) &&
                                (topOffset >= (railBottom - 12) && topOffset <= (railBottom + 56))

        if isOverBottomFlare {
            if !interaction.isSettingsHovered {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                    interaction.isSettingsHovered = true
                    interaction.hoveredIndex = nil
                    interaction.isDetailVisible = false
                }
            }
        } else {
            if interaction.isSettingsHovered {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                    interaction.isSettingsHovered = false
                }
            }

            // Rail hover corridor: rightmost 110pt of panel
            let isOverRail = location.x >= (frame.maxX - 110)
            if isOverRail {
                guard count > 0 else { return }

                let relY = topOffset - 42
                let rawIndex = Int(floor(relY / 88))
                let nextIndex = (relY >= 0 && rawIndex >= 0 && rawIndex < count) ? rawIndex : nil

                if interaction.hoveredIndex != nextIndex {
                    withAnimation(.spring(response: 0.16, dampingFraction: 0.90)) {
                        interaction.hoveredIndex = nextIndex
                        interaction.isDetailVisible = (nextIndex != nil)
                    }
                }
            }
        }
    }

    private var interactionRegion: NSRect {
        let frame = panel.frame
        let triggerRegion = NSRect(
            x: frame.maxX - 153,
            y: frame.maxY - 573,
            width: 153,
            height: 573)
        guard interaction.isHovered || interaction.pinnedOpen else {
            return triggerRegion
        }

        guard interaction.isDetailVisible else { return triggerRegion }
        let detailRegion = NSRect(
            x: frame.maxX - 440,
            y: frame.maxY - 573,
            width: 440,
            height: 573)
        return triggerRegion.union(detailRegion)
    }

    private func collapseFromOutsideClick() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            interaction.isHovered = false
            interaction.pinnedOpen = false
            interaction.isDetailVisible = false
            interaction.isSettingsHovered = false
            interaction.hoveredIndex = nil
            interaction.collapseToken &+= 1
        }
    }

}

// MARK: - Notch & Detail Views

struct NotchView: View {
    @Bindable var store: UsageStore
    @Bindable var interaction: NotchInteractionState

    private var activeStatuses: [ProviderStatus] {
        let detected = store.detectedStatuses
        if !detected.isEmpty {
            return detected
        }
        return store.statuses
    }

    private var activeIndex: Int? {
        guard let idx = interaction.hoveredIndex, idx >= 0, idx < activeStatuses.count else {
            return nil
        }
        return idx
    }

    private var activeStatus: ProviderStatus? {
        guard let idx = activeIndex else { return nil }
        return activeStatuses[idx]
    }

    private var isExpanded: Bool {
        interaction.isHovered || interaction.pinnedOpen || activeIndex != nil || interaction.isSettingsHovered
    }

    private var cardOffsetY: CGFloat {
        guard let idx = activeIndex else { return 16 }
        return CGFloat(idx) * 88 + 16
    }

    private var relativePointerY: CGFloat {
        70
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Transparent background that catches clicks outside to dismiss immediately
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        interaction.pinnedOpen = false
                        interaction.hoveredIndex = nil
                        interaction.isHovered = false
                        interaction.isDetailVisible = false
                        interaction.isSettingsHovered = false
                    }
                }

            HStack(alignment: .top, spacing: 10) {
                Spacer()

                // Floating Detail Card - directly bound to activeStatus & activeIndex
                if let status = activeStatus, (interaction.isHovered || interaction.pinnedOpen) {
                    DetailPopoverCard(status: status, pointerY: relativePointerY)
                        .id("DetailPopoverCard")
                        .offset(y: cardOffsetY)
                        .animation(.spring(response: 0.18, dampingFraction: 0.88), value: cardOffsetY)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.95, anchor: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(x: 12)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.96, anchor: .trailing))
                            )
                        )
                }

                // The Morphing Right-Edge Notch Rail
                morphingNotchRail
            }
        }
        .padding(.trailing, 0)
        .onChange(of: activeStatuses.count, initial: true) {
            interaction.providerCount = activeStatuses.count
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
    }

    // MARK: - Morphing Notch Rail

    private var hasNeedsAttention: Bool {
        activeStatuses.contains { $0.activity.needsAttention }
    }

    private var hasWorking: Bool {
        activeStatuses.contains { $0.activity.isWorking }
    }

    private var morphingNotchRail: some View {
        let items = activeStatuses

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, status in
                    ProviderRailItem(
                        status: status,
                        isHovered: interaction.hoveredIndex == index
                    )
                    .frame(width: 72, height: 76)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                            interaction.pinnedOpen.toggle()
                        }
                    }
                }

                if items.isEmpty {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(height: 50)
                }
            }
            .opacity(isExpanded ? 1.0 : 0.0)
            .scaleEffect(isExpanded ? 1.0 : 0.85, anchor: .topTrailing)
            .padding(.top, 48)
            .padding(.bottom, 48)
            .frame(width: 72)
        }
        .frame(width: isExpanded ? 72 : 10, height: isExpanded ? nil : 64, alignment: .topTrailing)
        .background(
            RightEdgeNotchShape(
                flareWidth: isExpanded ? 24 : 0,
                flareHeight: isExpanded ? 36 : 0,
                cornerRadius: isExpanded ? 28 : 8
            )
            .fill(Color.black)
            .shadow(color: Color.black.opacity(isExpanded ? 0.5 : 0.35), radius: isExpanded ? 14 : 5, x: isExpanded ? -4 : -1, y: 0)
        )
        .overlay(alignment: .topTrailing) {
            if !isExpanded {
                if hasNeedsAttention {
                    // Ambient Amber Beacon on Collapsed Notch Bezel
                    Circle()
                        .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.12), radius: 3)
                        .padding(.trailing, 2.5)
                        .padding(.top, 8)
                } else if hasWorking {
                    // Ambient Pure White Solid Dot on Collapsed Notch Bezel
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .padding(.trailing, 2.5)
                        .padding(.top, 8)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isExpanded {
                SettingsCornerButton(isHovered: interaction.isSettingsHovered)
                    .frame(width: 72, height: 52)
                    .offset(y: -4)
            }
        }
    }
}

// MARK: - Bottom Corner Settings Trigger

/// Solid pitch-black circular button with a bold white gear icon perfectly centered
/// on the provider column in the bottom flare of the notch.
struct SettingsCornerButton: View {
    let isHovered: Bool

    var body: some View {
        Button(action: openSettings) {
            ZStack {
                // Solid pitch-black circular background
                Circle()
                    .fill(Color.black)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHovered ? 0.35 : 0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.65), radius: 6, x: -1, y: 3)

                // Pure stark white settings gear icon
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isHovered ? 0 : -45))
            }
            .scaleEffect(isHovered ? 1.0 : 0.6)
            .opacity(isHovered ? 1.0 : 0.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - Live Agent Activity Motion Indicators

/// High-precision Swiss chronograph aperture ring with 12 calibrated radial ticks
/// and a razor-sharp orbiting laser needle (Zero glow, pure vector precision).
struct PrecisionChronographAperture: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Outer Precision Bezel Hairline
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)

            // 12 Calibrated Precision Ticks (Major Cardinals + Minor Subdivisions)
            ForEach(0..<12, id: \.self) { i in
                let isCardinal = (i % 3 == 0)
                Rectangle()
                    .fill(Color.white.opacity(isCardinal ? 0.65 : 0.28))
                    .frame(width: isCardinal ? 1.5 : 1, height: isCardinal ? 4.5 : 3)
                    .offset(y: -19.5)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // The Active Precision Orbiting Laser Arc
            Circle()
                .trim(from: 0, to: 0.33)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.65),
                            Color.white
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(120)
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))

            // Precision Diamond Head Index
            Rectangle()
                .fill(Color.white)
                .frame(width: 3.5, height: 3.5)
                .rotationEffect(.degrees(45))
                .offset(y: -21)
                .rotationEffect(.degrees(rotation + 120))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

/// Radiant warm amber sonar beacon indicating that user input or approval is required.
struct AgentNeedsAttentionBeacon: View {
    @State private var pulse: Bool = false
    private let accentColor = Color(red: 1.0, green: 0.70, blue: 0.12)

    var body: some View {
        ZStack {
            // Layer 1: Sonar Radar Ping expanding outward
            Circle()
                .stroke(accentColor.opacity(pulse ? 0.0 : 0.7), lineWidth: 1.5)
                .scaleEffect(pulse ? 1.32 : 1.0)

            // Layer 2: Warm ambient inner rim glow
            Circle()
                .stroke(accentColor.opacity(pulse ? 0.45 : 0.2), lineWidth: 2)

            // Layer 3: Jewel Badge at top-right
            ZStack {
                // Obsidian shadow base
                Circle()
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.black.opacity(0.6), radius: 3, x: 0, y: 1)

                // Glowing amber core with gentle heartbeat
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.15 : 0.95)

                // High-clarity spark
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 2.5, height: 2.5)
            }
            .offset(x: 15, y: -15)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Provider Rail Item (Ring + Percentage)

struct ProviderRailItem: View {
    let status: ProviderStatus
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var remainingPercent: Double {
        status.primary?.remainingPercent ?? 0
    }

    private var gaugeColor: Color {
        status.primary?.tierColor ?? Color(red: 0.18, green: 0.85, blue: 0.45)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Circular Gauge / Active Activity Ring
            ZStack {
                // Background Track Ring
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 3.5)

                // When STOPPED/IDLE: Display standard quota ring (Green / Yellow / Red based on remaining quota)
                if !status.activity.isWorking {
                    Circle()
                        .trim(from: 0, to: max(0.02, CGFloat(remainingPercent / 100)))
                        .stroke(
                            gaugeColor,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                // When RUNNING: Completely transforms into the Precision Chronograph Aperture (Zero glow, pure precision)
                if status.activity.isWorking {
                    if reduceMotion {
                        Circle()
                            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    } else {
                        PrecisionChronographAperture()
                    }
                } else if status.activity.needsAttention {
                    if reduceMotion {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                            .frame(width: 8, height: 8)
                            .offset(x: 15, y: -15)
                    } else {
                        AgentNeedsAttentionBeacon()
                    }
                }

                // Provider Logo Center
                ProviderLogo(provider: status.provider, size: 18)
                    .foregroundStyle(.white)
                    .scaleEffect(status.activity.isWorking ? 1.04 : 1.0)
            }
            .frame(width: 42, height: 42)
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isHovered)

            // Percentage Text
            Text("\(Int(remainingPercent.rounded()))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail Popover Card

struct DetailPopoverCard: View {
    let status: ProviderStatus
    let pointerY: CGFloat

    private var primaryWindow: UsageWindow? {
        status.primary
    }

    private var secondaryWindow: UsageWindow? {
        status.secondary
    }

    private var gaugeColor: Color {
        primaryWindow?.tierColor ?? Color(red: 0.18, green: 0.85, blue: 0.45)
    }

    private var cardWidth: CGFloat {
        312
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Logo + Provider Name + Live Activity Chip / Resets Countdown
            HStack(spacing: 8) {
                ProviderLogo(provider: status.provider, size: 19)
                    .foregroundStyle(.white)

                Text("\(status.provider.name) Usage")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(.white)

                Spacer()

                if status.activity.isWorking {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)

                        Text("Running")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.75)
                            )
                    )
                } else if status.activity.needsAttention {
                    HStack(spacing: 4.5) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.12))
                        Text("Action Required")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.12))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.72, blue: 0.12).opacity(0.14))
                            .overlay(Capsule().stroke(Color(red: 1.0, green: 0.72, blue: 0.12).opacity(0.38), lineWidth: 0.75))
                    )
                } else if let countdown = primaryWindow?.resetsInCountdown {
                    Text(countdown)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
            }

            // Primary Window: "Current session"
            VStack(alignment: .leading, spacing: 6) {
                Text("Current session")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))

                // Horizontal Progress Bar
                CustomProgressBar(
                    value: primaryWindow?.remainingPercent ?? 0,
                    gradient: primaryWindow?.gradient ?? defaultGradient
                )

                // Sub-labels: "73% Remaining" and "Resets Thu 12:00 AM"
                HStack {
                    Text("\(Int(primaryWindow?.remainingPercent.rounded() ?? 0))% Remaining")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.6))

                    Spacer()

                    if let resetText = primaryWindow?.formattedAbsoluteReset {
                        Text(resetText)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                }
            }

            // Secondary Window: "All models" / "Weekly"
            if let secondary = secondaryWindow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.provider == .claude ? "All models" : "Weekly")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))

                    CustomProgressBar(
                        value: secondary.remainingPercent,
                        gradient: secondary.gradient
                    )

                    HStack {
                        Text("\(Int(secondary.remainingPercent.rounded()))% Remaining")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.6))

                        Spacer()

                        if let resetText = secondary.formattedAbsoluteReset {
                            Text(resetText)
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.48))
                        }
                    }
                }
            }

            costUsageSection

            if let error = status.error {
                Text(error)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .padding(.trailing, 24) // Extra trailing padding for the pointer callout area
        .frame(width: cardWidth)
        .background(
            PopoverCalloutShape(pointerY: pointerY)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
                .overlay(
                    PopoverCalloutShape(pointerY: pointerY)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.65), radius: 24, x: -8, y: 10)
        )
    }

    @ViewBuilder
    private var costUsageSection: some View {
        if let cost = status.costUsage, cost.historyAvailable {
            VStack(alignment: .leading, spacing: 5) {
                Text("Token usage")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                HStack {
                    Text("Today")
                    Spacer()
                    Text(Self.tokenAndCost(tokens: cost.todayTokens, cost: cost.todayCostUSD))
                }
                HStack {
                    Text("Last 30 days")
                    Spacer()
                    Text(Self.tokenAndCost(tokens: cost.last30DaysTokens, cost: cost.last30DaysCostUSD))
                }
                .foregroundStyle(Color.white.opacity(0.6))
                .font(.system(size: 11.5, weight: .regular))
            }
        } else {
            EmptyView()
        }
    }

    private static func tokenAndCost(tokens: Int?, cost: Double?) -> String {
        guard let tokens else { return "—" }
        let tokenText = Self.compactTokenCount(tokens)
        guard let cost else { return tokenText }
        return "\(tokenText) · \(String(format: "$%.2f", cost))"
    }

    private static func compactTokenCount(_ tokens: Int) -> String {
        let value = Double(abs(tokens))
        let suffix: String
        let scaled: Double
        switch value {
        case 1_000_000_000...:
            scaled = value / 1_000_000_000
            suffix = "b"
        case 1_000_000...:
            scaled = value / 1_000_000
            suffix = "m"
        case 1_000...:
            scaled = value / 1_000
            suffix = "k"
        default:
            return tokens.formatted()
        }
        let precision = scaled >= 100 ? "%.0f" : scaled >= 10 ? "%.1f" : "%.2f"
        let sign = tokens < 0 ? "-" : ""
        return "\(sign)\(String(format: precision, scaled))\(suffix)"
    }

    private var defaultGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.22, green: 0.88, blue: 0.52), Color(red: 0.14, green: 0.78, blue: 0.38)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Custom Progress Bar

struct CustomProgressBar: View {
    let value: Double
    let gradient: LinearGradient

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fillWidth = max(4, width * CGFloat(min(100, max(0, value)) / 100))

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 5.5)

                // Colored Fill
                Capsule()
                    .fill(gradient)
                    .frame(width: fillWidth, height: 5.5)
            }
        }
        .frame(height: 5.5)
    }
}
