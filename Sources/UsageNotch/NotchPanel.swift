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

        if interactionRegion.contains(location) {
            if !interaction.isHovered {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    interaction.isHovered = true
                }
            }

            // Direct continuous vertical slot tracking when over the notch rail
            let isOverRail = location.x >= (frame.maxX - 84) && location.x <= frame.maxX
            if isOverRail {
                let topOffset = frame.maxY - location.y
                let contentTop: CGFloat = 48
                let slotHeight: CGFloat = 88
                let rawIndex = Int((topOffset - contentTop) / slotHeight)
                let count = interaction.providerCount
                let nextIndex = topOffset >= contentTop && rawIndex >= 0 && rawIndex < count ? rawIndex : nil
                if interaction.hoveredIndex != nextIndex {
                    withAnimation(.spring(response: 0.14, dampingFraction: 0.92)) {
                        interaction.hoveredIndex = nextIndex
                    }
                }
            }
        } else if interaction.isHovered || interaction.pinnedOpen {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                interaction.isHovered = false
                interaction.pinnedOpen = false
                interaction.isDetailVisible = false
                interaction.hoveredIndex = nil
                interaction.collapseToken &+= 1
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
            interaction.hoveredIndex = nil
            interaction.collapseToken &+= 1
        }
    }

}

// MARK: - Notch & Detail Views

struct NotchView: View {
    @Bindable var store: UsageStore
    @Bindable var interaction: NotchInteractionState

    @State private var hoveredProvider: ProviderID?
    @State private var selectedProvider: ProviderID?
    @State private var hoveredYPosition: CGFloat = 60
    @State private var autoHideTask: Task<Void, Never>?

    private var activeStatuses: [ProviderStatus] {
        let detected = store.detectedStatuses
        if !detected.isEmpty {
            return detected
        }
        return store.statuses
    }

    private var activeStatus: ProviderStatus? {
        let targetID = hoveredProvider ?? selectedProvider
        if let targetID {
            return activeStatuses.first { $0.provider == targetID }
        }
        return activeStatuses.first
    }

    private var isExpanded: Bool {
        interaction.isHovered || hoveredProvider != nil || interaction.pinnedOpen
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func scheduleAutoHide(delay: Double = 1.5) {
        cancelAutoHide()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                if !interaction.pinnedOpen {
                    hoveredProvider = nil
                    interaction.hoveredIndex = nil
                    interaction.isHovered = false
                }
            }
        }
    }

    private var cardOffsetY: CGFloat {
        max(16, ((hoveredYPosition - 70) / 88) * 74 + 16)
    }

    private var relativePointerY: CGFloat {
        hoveredYPosition - cardOffsetY
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Transparent background that catches clicks outside to dismiss immediately
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelAutoHide()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        interaction.pinnedOpen = false
                        hoveredProvider = nil
                        interaction.hoveredIndex = nil
                        interaction.isHovered = false
                    }
                }

            HStack(alignment: .top, spacing: 10) {
                Spacer()

                // Floating Detail Card - aligns with hovered provider level
                if let status = activeStatus, (hoveredProvider != nil || interaction.pinnedOpen || (interaction.isHovered && selectedProvider != nil)) {
                    DetailPopoverCard(status: status, pointerY: relativePointerY)
                        .id("DetailPopoverCard")
                        .offset(y: cardOffsetY)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.95, anchor: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(x: 12)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.96, anchor: .trailing))
                            )
                        )
                        .onHover { hovering in
                            if hovering {
                                cancelAutoHide()
                            } else {
                                scheduleAutoHide(delay: 1.5)
                            }
                        }
                }

                // The Morphing Right-Edge Notch Rail
                morphingNotchRail
            }
        }
        .padding(.trailing, 0)
        .onChange(of: activeStatuses.count, initial: true) {
            interaction.providerCount = activeStatuses.count
        }
        .onChange(of: hoveredProvider) {
            interaction.isDetailVisible = hoveredProvider != nil || interaction.pinnedOpen
        }
        .onChange(of: interaction.hoveredIndex) {
            if let idx = interaction.hoveredIndex, idx >= 0, idx < activeStatuses.count {
                cancelAutoHide()
                interaction.isHovered = true
                let transaction = Transaction(animation: nil)
                withTransaction(transaction) {
                    hoveredProvider = activeStatuses[idx].provider
                    selectedProvider = activeStatuses[idx].provider
                }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                    hoveredYPosition = CGFloat(idx) * 88 + 70
                }
            } else if interaction.hoveredIndex == nil && !interaction.pinnedOpen {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                    hoveredProvider = nil
                }
            }
        }
        .onChange(of: interaction.collapseToken) {
            cancelAutoHide()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                hoveredProvider = nil
                selectedProvider = nil
                interaction.hoveredIndex = nil
                interaction.pinnedOpen = false
                interaction.isHovered = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.18, dampingFraction: 0.88), value: hoveredYPosition)
    }

    // MARK: - Morphing Notch Rail

    private var morphingNotchRail: some View {
        let items = activeStatuses

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, status in
                    ProviderRailItem(
                        status: status,
                        isHovered: (hoveredProvider ?? (interaction.hoveredIndex.flatMap { items.indices.contains($0) ? items[$0].provider : nil })) == status.provider
                    )
                    .frame(width: 72, height: 76)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            cancelAutoHide()
                            interaction.isHovered = true
                            interaction.hoveredIndex = index
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                            selectedProvider = status.provider
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
        .clipped()
        .background(
            RightEdgeNotchShape(
                flareWidth: isExpanded ? 24 : 0,
                flareHeight: isExpanded ? 36 : 0,
                cornerRadius: isExpanded ? 28 : 8
            )
            .fill(Color.black)
            .shadow(color: Color.black.opacity(isExpanded ? 0.5 : 0.35), radius: isExpanded ? 14 : 5, x: isExpanded ? -4 : -1, y: 0)
        )
    }
}

// MARK: - Provider Rail Item (Ring + Percentage)

struct ProviderRailItem: View {
    let status: ProviderStatus
    let isHovered: Bool

    private var remainingPercent: Double {
        status.primary?.remainingPercent ?? 0
    }

    private var gaugeColor: Color {
        status.primary?.tierColor ?? Color(red: 0.18, green: 0.85, blue: 0.45)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Circular Gauge Ring
            ZStack {
                // Background Track Ring
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 3.5)

                // Active Filled Gauge showing remaining balance
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(remainingPercent / 100)))
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Provider Logo Center
                ProviderLogo(provider: status.provider, size: 18)
                    .foregroundStyle(.white)
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

    private var cardWidth: CGFloat {
        312
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Logo + Provider Name + Resets Countdown
            HStack(spacing: 8) {
                ProviderLogo(provider: status.provider, size: 19)
                    .foregroundStyle(.white)

                Text("\(status.provider.name) Usage")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(.white)

                Spacer()

                if let countdown = primaryWindow?.resetsInCountdown {
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
