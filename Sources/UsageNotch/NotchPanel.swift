import AppKit
import Observation
import SwiftUI

// MARK: - Glass

struct GlassMaterialView: NSViewRepresentable {
    let tint: ThemeColor

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *), AppSettings.activeWindowStyle == .liquidGlass {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.tintColor = tint.nsColor.withAlphaComponent(0.14)
            return glass
        }

        if AppSettings.activeWindowStyle == .solid {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = tint.solidNSColor.cgColor
            return solid
        }

        let translucent = NSVisualEffectView()
        translucent.material = .hudWindow
        translucent.blendingMode = .behindWindow
        translucent.state = .active
        translucent.wantsLayer = true
        translucent.layer?.backgroundColor = tint.nsColor.withAlphaComponent(0.14).cgColor
        return translucent
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.tintColor = tint.nsColor.withAlphaComponent(0.14)
        } else if let translucent = nsView as? NSVisualEffectView {
            translucent.layer?.backgroundColor = tint.nsColor.withAlphaComponent(0.14).cgColor
        }
    }
}

struct ThemedGlass<S: Shape>: View {
    let shape: S
    @AppStorage(AppSettings.themeColorKey) private var themeRaw = ThemeColor.red.rawValue

    private var currentTheme: ThemeColor {
        ThemeColor(rawValue: themeRaw) ?? .red
    }

    var body: some View {
        if #available(macOS 26.0, *), AppSettings.activeWindowStyle == .liquidGlass {
            shape
                .fill(Color.clear)
                .glassEffect(
                    .regular
                        .tint(currentTheme.color.opacity(0.14))
                        .interactive(),
                    in: shape
                )
                .overlay(glassReflection)
                .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.8))
        } else if AppSettings.activeWindowStyle == .solid {
            shape.fill(currentTheme.solidColor)
        } else {
            shape
                .fill(Color.clear)
                .background(GlassMaterialView(tint: currentTheme))
                .clipShape(shape)
                .overlay(glassReflection)
                .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: 0.8))
        }
    }

    private var glassReflection: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

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

/// The rail silhouette, mirrored when it is docked to the left edge.
struct OrientedRailShape: Shape {
    var flareWidth: CGFloat
    var flareHeight: CGFloat
    var cornerRadius: CGFloat
    var mirrored: Bool

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(flareWidth, AnimatablePair(flareHeight, cornerRadius)) }
        set {
            flareWidth = newValue.first
            flareHeight = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let path = RightEdgeNotchShape(
            flareWidth: flareWidth,
            flareHeight: flareHeight,
            cornerRadius: cornerRadius
        ).path(in: rect)
        guard mirrored else { return path }
        return path.applying(CGAffineTransform(
            a: -1, b: 0, c: 0, d: 1,
            tx: rect.minX + rect.maxX, ty: 0
        ))
    }
}

/// Smooth Apple-style Top Notch shape with true concave ear fillets and rounded bottom corners.
struct TopEdgeNotchShape: Shape {
    var flareWidth: CGFloat = 16
    var flareHeight: CGFloat = 16
    var cornerRadius: CGFloat = 20

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(flareWidth, AnimatablePair(flareHeight, cornerRadius)) }
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
        let fw = min(flareWidth, w * 0.25)
        let fh = min(flareHeight, h * 0.4)
        let cr = min(cornerRadius, max(2, min((w - 2 * fw) * 0.5, h - fh)))
        let k: CGFloat = 0.5522847

        // 1. Start at top-left screen boundary
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 2. Top-left concave ear fillet from (minX, minY) to (minX + fw, minY + fh)
        if fw > 0 && fh > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX + fw, y: rect.minY + fh),
                control1: CGPoint(x: rect.minX + fw * (1 - k), y: rect.minY),
                control2: CGPoint(x: rect.minX + fw, y: rect.minY + fh * k)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX + fw, y: rect.minY + fh))
        }

        // 3. Left straight vertical side
        path.addLine(to: CGPoint(x: rect.minX + fw, y: rect.maxY - cr))

        // 4. Bottom-left convex rounded corner
        path.addCurve(
            to: CGPoint(x: rect.minX + fw + cr, y: rect.maxY),
            control1: CGPoint(x: rect.minX + fw, y: rect.maxY - cr * (1 - k)),
            control2: CGPoint(x: rect.minX + fw + cr * (1 - k), y: rect.maxY)
        )

        // 5. Bottom horizontal straight edge
        path.addLine(to: CGPoint(x: rect.maxX - fw - cr, y: rect.maxY))

        // 6. Bottom-right convex rounded corner
        path.addCurve(
            to: CGPoint(x: rect.maxX - fw, y: rect.maxY - cr),
            control1: CGPoint(x: rect.maxX - fw - cr * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.maxX - fw, y: rect.maxY - cr * (1 - k))
        )

        // 7. Right straight vertical side
        path.addLine(to: CGPoint(x: rect.maxX - fw, y: rect.minY + fh))

        // 8. Top-right concave ear fillet from (maxX - fw, minY + fh) to (maxX, minY)
        if fw > 0 && fh > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control1: CGPoint(x: rect.maxX - fw, y: rect.minY + fh * k),
                control2: CGPoint(x: rect.maxX - fw * (1 - k), y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // 9. Close along top boundary
        path.closeSubpath()
        return path
    }
}

/// Bottom-edge notch: the top is rounded while the attached bottom edge
/// uses the same concave ear treatment as the hardware notch.
struct BottomIslandCapsule: Shape {
    var flareWidth: CGFloat = 24
    var flareHeight: CGFloat = 20
    var cornerRadius: CGFloat = 24

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(flareWidth, AnimatablePair(flareHeight, cornerRadius)) }
        set {
            flareWidth = newValue.first
            flareHeight = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let path = TopEdgeNotchShape(
            flareWidth: flareWidth,
            flareHeight: flareHeight,
            cornerRadius: cornerRadius
        ).path(in: rect)
        return path.applying(CGAffineTransform(
            a: 1, b: 0, c: 0, d: -1,
            tx: 0, ty: rect.minY + rect.maxY
        ))
    }
}

/// Geometry and metrics layout for the dynamic Bottom Notch bar.
enum HorizontalBarLayout {
    static let itemWidth: CGFloat = 68
    static let itemSpacing: CGFloat = 10
    static let dividerWidth: CGFloat = 1
    static let dividerSpacing: CGFloat = 8
    static let settingsWidth: CGFloat = 65
    static let sidePadding: CGFloat = 34
    static let barHeight: CGFloat = 74
    static let collapsedWidth: CGFloat = 64
    static let collapsedHeight: CGFloat = 20

    static func expandedWidth(for count: Int) -> CGFloat {
        let actualCount = max(1, count)
        let itemsWidth = CGFloat(actualCount) * itemWidth + CGFloat(max(0, actualCount - 1)) * itemSpacing
        // The settings button is positioned in the curved end-cap, outside
        // the provider row, so it must not reserve empty row space.
        return itemsWidth + (sidePadding * 2)
    }

    static func itemCenterX(for index: Int, totalCount: Int) -> CGFloat {
        let totalW = expandedWidth(for: totalCount)
        let startX = -totalW / 2 + sidePadding
        return startX + CGFloat(index) * (itemWidth + itemSpacing) + (itemWidth / 2)
    }

    static func settingsCenterX(for totalCount: Int) -> CGFloat {
        let totalW = expandedWidth(for: totalCount)
        return totalW / 2 + 4
    }
}

/// Popover card with an animatable triangular callout beak pointing at the hovered item.
struct PopoverCalloutShape: Shape {
    var pointerY: CGFloat
    var cornerRadius: CGFloat = 16
    var pointerWidth: CGFloat = 10
    var pointerHeight: CGFloat = 18
    var pointerOnLeft = false

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
        guard pointerOnLeft else { return path }
        return path.applying(CGAffineTransform(
            a: -1, b: 0, c: 0, d: 1,
            tx: rect.minX + rect.maxX, ty: 0
        ))
    }
}

struct VerticalPopoverCalloutShape: Shape {
    var pointerX: CGFloat
    var pointerOnTop: Bool
    var cornerRadius: CGFloat = 16
    var pointerWidth: CGFloat = 18
    var pointerHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let cardRect = CGRect(
            x: rect.minX,
            y: pointerOnTop ? rect.minY + pointerHeight : rect.minY,
            width: rect.width,
            height: rect.height - pointerHeight
        )
        let clampedX = min(max(pointerX, cardRect.minX + cornerRadius + pointerWidth / 2),
                           cardRect.maxX - cornerRadius - pointerWidth / 2)
        var path = Path(roundedRect: cardRect, cornerRadius: cornerRadius)
        var pointer = Path()
        if pointerOnTop {
            pointer.move(to: CGPoint(x: clampedX - pointerWidth / 2, y: cardRect.minY))
            pointer.addLine(to: CGPoint(x: clampedX, y: rect.minY))
            pointer.addLine(to: CGPoint(x: clampedX + pointerWidth / 2, y: cardRect.minY))
        } else {
            pointer.move(to: CGPoint(x: clampedX - pointerWidth / 2, y: cardRect.maxY))
            pointer.addLine(to: CGPoint(x: clampedX, y: rect.maxY))
            pointer.addLine(to: CGPoint(x: clampedX + pointerWidth / 2, y: cardRect.maxY))
        }
        pointer.closeSubpath()
        path.addPath(pointer)
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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
    }

    func place() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let panelWidth: CGFloat = 640
        let panelHeight: CGFloat = 480
        let position = NotchPosition(rawValue: UserDefaults.standard.string(forKey: AppSettings.notchPositionKey) ?? "") ?? .right
        let frame = screen.visibleFrame

        // The rail is the right-most 72pt of the canonical panel. Anchor that
        // rail to the selected screen edge rather than centering the whole panel.
        let origin: CGPoint
        switch position {
        case .right:
            origin = CGPoint(
                x: frame.maxX - panelWidth,
                y: max(frame.minY + 20, frame.maxY - panelHeight - 12))
        case .leftCenter:
            origin = CGPoint(
                x: frame.minX,
                y: max(frame.minY + 20, frame.maxY - panelHeight - 12))
        case .bottomCenter:
            origin = CGPoint(x: frame.midX - panelWidth / 2, y: frame.minY)
        }

        setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
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
    var position: NotchPosition = NotchPosition(rawValue: UserDefaults.standard.string(forKey: AppSettings.notchPositionKey) ?? "") ?? .right
    var displayMode: OverlayDisplayMode = AppSettings.overlayDisplayMode
}

@MainActor
final class NotchPanelController {
    let panel = NotchPanel()
    private let interaction = NotchInteractionState()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var autoCollapseTask: Task<Void, Never>?

    func settingsDidChange() {
        panel.place()
        interaction.position = NotchPosition(rawValue: UserDefaults.standard.string(forKey: AppSettings.notchPositionKey) ?? "") ?? .right
        interaction.displayMode = AppSettings.overlayDisplayMode
        interaction.panelFrame = panel.frame
        interaction.collapseToken &+= 1
    }

    func show(store: UsageStore) {
        panel.place()
        interaction.position = NotchPosition(rawValue: UserDefaults.standard.string(forKey: AppSettings.notchPositionKey) ?? "") ?? .right
        interaction.displayMode = AppSettings.overlayDisplayMode
        interaction.panelFrame = panel.frame

        let hostedView = TrackingHostingView(rootView: NotchView(
            store: store,
            interaction: interaction
        ))

        hostedView.onExit = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.autoCollapseTask?.cancel()
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
                self.autoCollapseTask?.cancel()
            }
            return
        }

        if !interaction.isHovered {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                interaction.isHovered = true
            }
        }

        if interaction.position == .bottomCenter {
            updateHorizontalHover(at: location, in: frame)
            return
        }

        let topOffset = frame.maxY - location.y
        let count = interaction.providerCount
        // The provider stack ends after its item frames, spacing, and bottom padding.
        let railBottom = CGFloat(count) * 88 + 84
        let settingsXRange = interaction.position == .leftCenter
            ? (frame.minX...(frame.minX + 72))
            : ((frame.maxX - 72)...frame.maxX)
        let isOverSettingsButton = interaction.isSettingsHovered &&
                                   settingsXRange.contains(location.x) &&
                                   topOffset >= (railBottom - 42) &&
                                   topOffset <= (railBottom + 30)

        // Activate settings only from the empty space below the provider stack.
        let bottomCornerXRange = interaction.position == .leftCenter
            ? (frame.minX...(frame.minX + 90))
            : ((frame.maxX - 90)...frame.maxX)
        let isOverBottomCorner = (bottomCornerXRange.contains(location.x) &&
                                  (topOffset >= railBottom && topOffset <= (railBottom + 80))) ||
                                 isOverSettingsButton

        if isOverBottomCorner {
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

            // Rail hover corridor, anchored to the selected edge.
            let isOverRail = interaction.position == .leftCenter
                ? location.x <= (frame.minX + 110)
                : location.x >= (frame.maxX - 110)
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

    private func updateHorizontalHover(at location: CGPoint, in frame: NSRect) {
        let count = interaction.providerCount
        let barHeight = HorizontalBarLayout.barHeight
        let isWithinBarY = location.y >= frame.minY && location.y <= frame.minY + barHeight + 16
        let settingsCenterX = frame.midX + HorizontalBarLayout.settingsCenterX(for: count)
        let isWithinSettingsRegion = location.y >= frame.minY && location.y <= frame.minY + 165
            && abs(location.x - settingsCenterX) <= 98
        let isOverSettings = isWithinSettingsRegion

        // If the mouse is within the detail area, maintain the current item.
        let isWithinPopoverY = location.y > frame.minY + barHeight + 16 && location.y <= frame.minY + 340

        if isWithinPopoverY && interaction.hoveredIndex != nil && interaction.isDetailVisible {
            return
        }

        let relX = location.x - frame.midX

        if isOverSettings {
            if !interaction.isSettingsHovered {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                    interaction.isSettingsHovered = true
                    interaction.hoveredIndex = nil
                    interaction.isDetailVisible = false
                }
            }
            return
        }

        if interaction.isSettingsHovered {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                interaction.isSettingsHovered = false
            }
        }

        guard count > 0, isWithinBarY else { return }

        var foundIndex: Int? = nil
        for i in 0..<count {
            let itemCenterX = HorizontalBarLayout.itemCenterX(for: i, totalCount: count)
            if abs(relX - itemCenterX) <= (HorizontalBarLayout.itemWidth / 2 + 3) {
                foundIndex = i
                break
            }
        }

        if interaction.hoveredIndex != foundIndex {
            withAnimation(.spring(response: 0.16, dampingFraction: 0.90)) {
                interaction.hoveredIndex = foundIndex
                interaction.isDetailVisible = foundIndex != nil
            }
        }
    }

    private var interactionRegion: NSRect {
        let frame = panel.frame
        if interaction.position == .bottomCenter {
            return NSRect(
                x: frame.midX - 763 / 2,
                y: frame.minY,
                width: 763,
                height: 199
            )
        }

        let triggerRegion = NSRect(
            x: interaction.position == .leftCenter ? frame.minX : frame.maxX - 153,
            y: frame.maxY - 573,
            width: 153,
            height: 573)
        guard interaction.isHovered || interaction.pinnedOpen else {
            return triggerRegion
        }

        guard interaction.isDetailVisible else { return triggerRegion }
        let detailRegion = NSRect(
            x: interaction.position == .leftCenter ? frame.minX : frame.maxX - 440,
            y: frame.maxY - 573,
            width: 440,
            height: 573)
        return triggerRegion.union(detailRegion)
    }

    private func collapseFromOutsideClick() {
        autoCollapseTask?.cancel()
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
    @AppStorage(AppSettings.themeColorKey) private var themeRaw = ThemeColor.red.rawValue

    private var currentTheme: ThemeColor {
        ThemeColor(rawValue: themeRaw) ?? .red
    }

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

    private var shouldShowDetailCard: Bool {
        interaction.isDetailVisible || interaction.pinnedOpen
    }

    private var isExpanded: Bool {
        switch interaction.displayMode {
        case .alwaysExpanded:
            true
        case .hover:
            interaction.isHovered || interaction.pinnedOpen || activeIndex != nil || interaction.isSettingsHovered
        case .hidden:
            false
        }
    }

    private var cardOffsetY: CGFloat {
        guard let idx = activeIndex else { return 16 }
        return CGFloat(idx) * 88 + 16
    }

    private var relativePointerY: CGFloat {
        70
    }

    private var isLeft: Bool {
        interaction.position == .leftCenter
    }

    private var isBottom: Bool {
        interaction.position == .bottomCenter
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

            if interaction.position == .bottomCenter {
                horizontalLayout
            } else {
                verticalLayout
            }
        }
        .padding(.trailing, 0)
        .opacity(interaction.displayMode == .hidden ? 0 : 1)
        .allowsHitTesting(interaction.displayMode != .hidden)
        .ignoresSafeArea()
        .onChange(of: activeStatuses.count, initial: true) {
            interaction.providerCount = activeStatuses.count
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(
            .spring(response: AppSettings.animationDuration, dampingFraction: 0.88, blendDuration: 0.12),
            value: isExpanded
        )
    }

    private var verticalLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            if isLeft { morphingNotchRail } else { Spacer() }

            if let status = activeStatus, (interaction.isHovered || interaction.pinnedOpen) {
                DetailPopoverCard(status: status, pointerY: relativePointerY, pointerOnLeft: isLeft)
                    .id("DetailPopoverCard")
                    .offset(y: cardOffsetY)
                    .animation(.spring(response: 0.18, dampingFraction: 0.88), value: cardOffsetY)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.95, anchor: isLeft ? .leading : .trailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(x: isLeft ? -12 : 12)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: isLeft ? .leading : .trailing))
                        )
                    )
            }

            if isLeft { Spacer() } else { morphingNotchRail }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var horizontalLayoutMetrics: (cardOffsetX: CGFloat, pointerX: CGFloat) {
        guard let idx = activeIndex else { return (0, 156) }
        let count = activeStatuses.count
        let targetItemCenterX = HorizontalBarLayout.itemCenterX(for: idx, totalCount: count)

        let cardWidth: CGFloat = 312
        let clampedCardOffsetX = min(max(targetItemCenterX, -140), 140)
        let relativePointerX = (targetItemCenterX - clampedCardOffsetX) + (cardWidth / 2)
        let clampedPointerX = min(max(relativePointerX, 28), cardWidth - 28)
        return (clampedCardOffsetX, clampedPointerX)
    }

    private var horizontalLayout: some View {
        let metrics = horizontalLayoutMetrics
        return VStack(spacing: 8) {
            Spacer(minLength: 0)

            if let status = activeStatus, (interaction.isHovered || interaction.pinnedOpen) {
                DetailPopoverCard(
                    status: status,
                    pointerY: relativePointerY,
                    verticalPointerOnTop: false,
                    pointerX: metrics.pointerX
                )
                .offset(x: metrics.cardOffsetX)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }

            bottomIslandBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Floating Island (.bottomCenter)

    private var bottomIslandBar: some View {
        let items = activeStatuses
        let count = items.count
        let width = isExpanded ? HorizontalBarLayout.expandedWidth(for: count) : HorizontalBarLayout.collapsedWidth
        let height = isExpanded ? HorizontalBarLayout.barHeight : HorizontalBarLayout.collapsedHeight

        let shape = BottomIslandCapsule(
            flareWidth: isExpanded ? 20 : 0,
            flareHeight: isExpanded ? 16 : 0,
            cornerRadius: isExpanded ? 20 : 8
        )

        return ZStack {
            if isExpanded {
                HStack(spacing: HorizontalBarLayout.itemSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, status in
                        ProviderRailItem(status: status, isHovered: interaction.hoveredIndex == index)
                            .frame(width: HorizontalBarLayout.itemWidth, height: 58)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                guard hovering else { return }
                                interaction.hoveredIndex = index
                                interaction.isDetailVisible = true
                                interaction.isHovered = true
                            }
                            .onTapGesture {
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                                    interaction.pinnedOpen.toggle()
                                }
                            }
                    }

                }
                .padding(.horizontal, HorizontalBarLayout.sidePadding)
                .padding(.top, 8)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .bottom))
                            .animation(.spring(response: AppSettings.animationDuration, dampingFraction: 0.86)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .bottom))
                            .animation(.spring(response: AppSettings.animationDuration, dampingFraction: 0.86))
                    )
                )
            } else {
                bottomIslandAmbientView
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .background(
            shape
                .fill(Color.clear)
                .background(ThemedGlass(shape: shape))
                .overlay(
                    currentTheme.color.opacity(0.14)
                        .clipShape(shape)
                )
                .overlay(shape.stroke(Color.white.opacity(isExpanded ? 0.15 : 0.08), lineWidth: 0.75))
                .shadow(
                    color: Color.black.opacity(isExpanded ? 0.55 : 0.35),
                    radius: isExpanded ? 18 : 5,
                    y: -1
                )
        )
        .overlay(alignment: .topTrailing) {
            if isExpanded {
                SettingsCornerButton(
                    isHovered: interaction.isSettingsHovered,
                    onInteract: { interaction.pinnedOpen = true }
                )
                .scaleEffect(0.9)
                .offset(x: 40, y: 10)
            }
        }
    }

    private var bottomIslandAmbientView: some View {
        HStack(spacing: 8) {
            if hasNeedsAttention {
                Circle()
                    .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                    .frame(width: 5, height: 5)
                    .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.12), radius: 3)
                    .padding(.top, 4)
            } else if hasWorking {
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .padding(.top, 4)
            }
        }
        .frame(height: 20)
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
                    .onHover { hovering in
                        guard hovering else { return }
                        interaction.hoveredIndex = index
                        interaction.isDetailVisible = true
                        interaction.isHovered = true
                    }
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
            .animation(
                .spring(response: AppSettings.animationDuration, dampingFraction: 0.86),
                value: isExpanded
            )
            .padding(.top, 48)
            .padding(.bottom, 48)
            .frame(width: 72)
        }
        .frame(width: isExpanded ? 72 : 20, height: isExpanded ? nil : 64, alignment: isLeft ? .topLeading : .topTrailing)
        .background(
            OrientedRailShape(
                flareWidth: isExpanded ? 24 : 0,
                flareHeight: isExpanded ? 36 : 0,
                cornerRadius: isExpanded ? 28 : 8,
                mirrored: isLeft
            )
            .fill(Color.clear)
            .background(
                ThemedGlass(
                    shape: OrientedRailShape(
                        flareWidth: isExpanded ? 24 : 0,
                        flareHeight: isExpanded ? 36 : 0,
                        cornerRadius: isExpanded ? 28 : 8,
                        mirrored: isLeft
                    )
                )
            )
            .overlay(
                currentTheme.color.opacity(0.14)
                    .clipShape(
                        OrientedRailShape(
                            flareWidth: isExpanded ? 24 : 0,
                            flareHeight: isExpanded ? 36 : 0,
                            cornerRadius: isExpanded ? 28 : 8,
                            mirrored: isLeft
                        )
                    )
            )
            .shadow(color: Color.black.opacity(isExpanded ? 0.5 : 0.35), radius: isExpanded ? 14 : 5, x: isExpanded ? -4 : -1, y: 0)
        )
        .overlay(alignment: isLeft ? .topLeading : .topTrailing) {
            if !isExpanded {
                if hasNeedsAttention {
                    // Ambient Amber Beacon on Collapsed Notch Bezel
                    Circle()
                        .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.12), radius: 3)
                        .padding(.trailing, isLeft ? 0 : 6)
                        .padding(.leading, isLeft ? 6 : 0)
                        .padding(.top, 8)
                } else if hasWorking {
                    // Ambient Pure White Solid Dot on Collapsed Notch Bezel
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .padding(.trailing, isLeft ? 0 : 6)
                        .padding(.leading, isLeft ? 6 : 0)
                        .padding(.top, 8)
                }
            }
        }
        .overlay(alignment: isLeft ? .bottomTrailing : .bottomLeading) {
            if isExpanded {
                SettingsCornerButton(
                    isHovered: interaction.isSettingsHovered,
                    onInteract: { interaction.pinnedOpen = true }
                )
                .offset(x: isLeft ? -1 : 1, y: 30)
            }
        }
    }
}

// MARK: - Bottom Corner Settings Trigger

/// Solid pitch-black circular button with a crisp white outline gear, flush with the notch rail
/// and nestled comfortably below the curve as shown in the reference image.
struct SettingsCornerButton: View {
    let isHovered: Bool
    let onInteract: () -> Void
    @AppStorage(AppSettings.themeColorKey) private var themeRaw = ThemeColor.red.rawValue

    private var currentTheme: ThemeColor {
        ThemeColor(rawValue: themeRaw) ?? .red
    }

    var body: some View {
        Button {
            onInteract()
            openSettings()
        } label: {
            ZStack {
                // Solid pitch-black circular background
                ThemedGlass(shape: Circle())
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .fill(currentTheme.color.opacity(0.14))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHovered ? 0.35 : 0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.65), radius: 6, x: -1, y: 2)

                // Clean white outline gear icon matching reference
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isHovered ? 0 : -45))
            }
            .scaleEffect(isHovered ? 1.0 : 0.6)
            .opacity(isHovered ? 1.0 : 0.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 72)
        .contentShape(Rectangle())
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openUsageNotchSettings, object: nil)
    }
}

/// Sleek inline circular settings gear button that is seamlessly integrated into horizontal Dynamic Notch / Island bars.
struct SettingsInlineButton: View {
    let isHovered: Bool
    let onInteract: () -> Void

    var body: some View {
        Button {
            onInteract()
            NotificationCenter.default.post(name: .openUsageNotchSettings, object: nil)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.20 : 0.08))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHovered ? 0.40 : 0.16), lineWidth: 0.8)
                    )

                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.75))
                    .rotationEffect(.degrees(isHovered ? 45 : 0))
            }
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Live Agent Activity Motion Indicators

/// High-precision Swiss chronograph aperture perimeter tracer that glides along
/// the exact outer path of any selected shape (Circle, Squircle, Rounded, Square)
/// without rotating the shape geometry across the center.
struct PrecisionChronographAperture: View {
    var shape: ProviderIconShape = .circle

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycleDuration = AppSettings.activityAnimationDuration
            let progress = (time.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration

            ZStack {
                // Outer Precision Bezel Hairline Track in chosen shape
                strokeBezel(Color.white.opacity(0.20), lineWidth: 1.2)

                // Perimeter laser beam traveling around the chosen shape's edge
                ShapePerimeterTracer(
                    shape: shape,
                    progress: progress,
                    strokeStyle: StrokeStyle(lineWidth: 3.4, lineCap: .round)
                )
            }
        }
    }

    @ViewBuilder
    private func strokeBezel(_ color: Color, lineWidth: CGFloat) -> some View {
        switch shape {
        case .circle:
            Circle().stroke(color, lineWidth: lineWidth)
        case .squircle:
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color, lineWidth: lineWidth)
        case .rounded:
            RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(color, lineWidth: lineWidth)
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(color, lineWidth: lineWidth)
        }
    }
}

/// Continuous perimeter tracer traveling along any geometric shape path
struct ShapePerimeterTracer: View {
    let shape: ProviderIconShape
    let progress: Double // 0.0 ... 1.0
    let length: Double = 0.28 // fraction of perimeter
    let strokeStyle: StrokeStyle

    var body: some View {
        ZStack {
            // Primary segment
            let start1 = progress
            let end1 = min(1.0, progress + length)
            if start1 < 1.0 {
                trimmedShape(from: CGFloat(start1), to: CGFloat(end1))
            }

            // Wrap-around segment past the 1.0 boundary
            if progress + length > 1.0 {
                let end2 = (progress + length) - 1.0
                trimmedShape(from: 0.0, to: CGFloat(min(1.0, end2)))
            }
        }
    }

    @ViewBuilder
    private func trimmedShape(from start: CGFloat, to end: CGFloat) -> some View {
        let beamColor = Color.white

        switch shape {
        case .circle:
            Circle()
                .trim(from: start, to: end)
                .stroke(beamColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .squircle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .trim(from: start, to: end)
                .stroke(beamColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .rounded:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .trim(from: start, to: end)
                .stroke(beamColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .trim(from: start, to: end)
                .stroke(beamColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Radiant warm amber sonar beacon indicating that user input or approval is required.
struct AgentNeedsAttentionBeacon: View {
    var shape: ProviderIconShape = .circle
    @State private var pulse: Bool = false
    private let accentColor = Color(red: 1.0, green: 0.70, blue: 0.12)

    var body: some View {
        ZStack {
            // Layer 1: Sonar Radar Ping expanding outward
            strokeBeacon(accentColor.opacity(pulse ? 0.0 : 0.7), lineWidth: 1.5)
                .scaleEffect(pulse ? 1.32 : 1.0)

            // Layer 2: Warm ambient inner rim glow
            strokeBeacon(accentColor.opacity(pulse ? 0.45 : 0.2), lineWidth: 2)

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

    @ViewBuilder
    private func strokeBeacon(_ color: Color, lineWidth: CGFloat) -> some View {
        switch shape {
        case .circle:
            Circle().stroke(color, lineWidth: lineWidth)
        case .squircle:
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color, lineWidth: lineWidth)
        case .rounded:
            RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(color, lineWidth: lineWidth)
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(color, lineWidth: lineWidth)
        }
    }
}

// MARK: - Provider Rail Item (Ring + Percentage)

struct ProviderRailItem: View {
    let status: ProviderStatus
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettings.providerIconShapeKey) private var iconShapeRaw = ProviderIconShape.circle.rawValue

    private var currentShape: ProviderIconShape {
        ProviderIconShape(rawValue: iconShapeRaw) ?? .circle
    }

    private var remainingPercent: Double {
        status.primary?.remainingPercent ?? 0
    }

    private var gaugeColor: Color {
        status.primary?.tierColor ?? Color(red: 0.18, green: 0.85, blue: 0.45)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Gauge / Active Activity Frame
            ZStack {
                // Background Track
                trackView

                // When STOPPED/IDLE: Display standard quota gauge
                if !status.activity.isWorking {
                    gaugeFillView
                }

                // When RUNNING: Precision Chronograph Aperture
                if status.activity.isWorking {
                    if reduceMotion {
                        chronographFallbackView
                    } else {
                        PrecisionChronographAperture(shape: currentShape)
                    }
                } else if status.activity.needsAttention {
                    if reduceMotion {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                            .frame(width: 8, height: 8)
                            .offset(x: 15, y: -15)
                    } else {
                        AgentNeedsAttentionBeacon(shape: currentShape)
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
                .font(.custom("Spline Sans Mono", size: 13).weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 18, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trackView: some View {
        switch currentShape {
        case .circle:
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 5.2)
        case .squircle:
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 5.2)
        case .rounded:
            RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 5.2)
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 5.2)
        }
    }

    @ViewBuilder
    private var gaugeFillView: some View {
        let trimEnd = max(0.02, CGFloat(remainingPercent / 100))
        let strokeStyle = StrokeStyle(lineWidth: 5.2, lineCap: .round)
        switch currentShape {
        case .circle:
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(gaugeColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .squircle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .trim(from: 0, to: trimEnd)
                .stroke(gaugeColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .rounded:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .trim(from: 0, to: trimEnd)
                .stroke(gaugeColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .trim(from: 0, to: trimEnd)
                .stroke(gaugeColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder
    private var chronographFallbackView: some View {
        let strokeStyle = StrokeStyle(lineWidth: 3.2, lineCap: .round)
        switch currentShape {
        case .circle:
            Circle().stroke(Color.white.opacity(0.85), style: strokeStyle).rotationEffect(.degrees(-90))
        case .squircle:
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.85), style: strokeStyle).rotationEffect(.degrees(-90))
        case .rounded:
            RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.85), style: strokeStyle).rotationEffect(.degrees(-90))
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.white.opacity(0.85), style: strokeStyle).rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Detail Popover Card

struct DetailPopoverCard: View {
    let status: ProviderStatus
    let pointerY: CGFloat
    let pointerOnLeft: Bool
    let verticalPointerOnTop: Bool?
    let pointerX: CGFloat?
    @AppStorage(AppSettings.themeColorKey) private var themeRaw = ThemeColor.red.rawValue

    private var currentTheme: ThemeColor {
        ThemeColor(rawValue: themeRaw) ?? .red
    }

    init(
        status: ProviderStatus,
        pointerY: CGFloat,
        pointerOnLeft: Bool = false,
        verticalPointerOnTop: Bool? = nil,
        pointerX: CGFloat? = nil
    ) {
        self.status = status
        self.pointerY = pointerY
        self.pointerOnLeft = pointerOnLeft
        self.verticalPointerOnTop = verticalPointerOnTop
        self.pointerX = pointerX
    }

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
        .padding(.vertical, verticalPointerOnTop == nil ? 14 : 20)
        .padding(.leading, pointerOnLeft ? 24 : 16)
        .padding(.trailing, pointerOnLeft ? 16 : 24)
        .frame(width: cardWidth)
        .background { cardBackground }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let verticalPointerOnTop {
            let shape = VerticalPopoverCalloutShape(
                pointerX: pointerX ?? (cardWidth / 2),
                pointerOnTop: verticalPointerOnTop
            )
            ThemedGlass(shape: shape)
                .overlay(currentTheme.color.opacity(0.14).clipShape(shape))
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.65), radius: 24, y: verticalPointerOnTop ? 10 : -10)
        } else {
            let shape = PopoverCalloutShape(pointerY: pointerY, pointerOnLeft: pointerOnLeft)
            ThemedGlass(shape: shape)
                .overlay(currentTheme.color.opacity(0.14).clipShape(shape))
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.65), radius: 24, x: pointerOnLeft ? 8 : -8, y: 10)
        }
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
