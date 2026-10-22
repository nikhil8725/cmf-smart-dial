import Observation
import SwiftUI

/// UI-only state the panel drives: whether the dial is out and where the
/// tether dot sits. App state stays in `DialModel`.
@Observable
final class DialPresentation {
    var isShown = false
    /// Horizontal offset of the tether dot from the dial's centre, for when the
    /// panel slides left near the screen edge but the dot stays under the glyph.
    var tetherOffset: CGFloat = 0
}

/// The radial mode picker (DESIGN.md, "Dial geometry"), drawn on a 260 × 260 canvas.
struct DialView: View {
    let model: DialModel
    let presentation: DialPresentation
    /// Mouse: a click on a segment selects it, a click on the knob presses.
    var onSelect: (ModeID) -> Void = { _ in }
    var onPress: () -> Void = {}
    /// The tether dot belongs under the menu bar glyph; previews can leave it out.
    var showsTether = true
    /// The app icon leaves the knob's name out; text is noise at icon sizes.
    var showsKnobLabel = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many times each segment has become selected; drives its icon tick.
    @State private var tickCounts: [Int: Int] = [:]
    @State private var dragStartAngle: Double? = nil
    @State private var accumulatedDrag: Double = 0

    private var isShown: Bool { presentation.isShown }

    private var detentAnimation: Animation? {
        if reduceMotion { return nil }
        // Read from the model, so the first fast step already runs fast.
        return model.isFastSpin ? DialMotion.detentFast : DialMotion.detent
    }

    var body: some View {
        ZStack {
            wellBacking
            RingView(
                highlightAngle: model.highlightAngle,
                pressCount: model.pressCount,
                // Inside a mode (the app fan) the highlight holds, slightly receded.
                segmentOpacity: model.isFanOpen ? 0.9 : 1,
                detentAnimation: detentAnimation,
                reduceMotion: reduceMotion
            )
            icons
            if showsTether { tether }
            well
            KnobView(
                angle: model.knobAngle,
                mode: model.selectedMode,
                pressCount: model.pressCount,
                isShown: isShown,
                turnAnimation: detentAnimation,
                reduceMotion: reduceMotion,
                showsLabel: showsKnobLabel
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    let dx = value.location.x - DialPath.centre.x
                    let dy = value.location.y - DialPath.centre.y
                    let currentAngle = atan2(dx, -dy) * 180 / .pi
                    if let start = dragStartAngle {
                        var delta = currentAngle - start
                        if delta > 180 { delta -= 360 }
                        else if delta < -180 { delta += 360 }
                        accumulatedDrag += delta
                        if abs(accumulatedDrag) >= 28.0 {
                            let steps = Int(accumulatedDrag / 28.0)
                            if steps != 0 {
                                model.handle(.turn(steps), from: "dialDrag")
                                accumulatedDrag -= Double(steps) * 28.0
                            }
                        }
                    }
                    dragStartAngle = currentAngle
                }
                .onEnded { _ in
                    dragStartAngle = nil
                    accumulatedDrag = 0
                }
        )
        .simultaneousGesture(SpatialTapGesture().onEnded { click(at: $0.location) })
        .modifier(SummonEffect(isShown: isShown, reduceMotion: reduceMotion))
        .onChange(of: model.detentCount) {
            tickCounts[model.segmentIndex(of: model.selectedMode), default: 0] += 1
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dial, \(model.selectedMode.label) selected")
    }

    // MARK: - Layers

    private var icons: some View {
        ForEach(Array(model.ringOrder.enumerated()), id: \.element) { index, mode in
            SegmentIcon(
                mode: mode,
                isSelected: mode == model.selectedMode,
                isEnabled: model.modes.contains(mode),
                tick: tickCounts[index, default: 0],
                isShown: isShown,
                summonDelay: DialMotion.iconStagger * Double(index),
                reduceMotion: reduceMotion
            )
            .position(DialPath.point(radius: DialGeometry.iconRadius, angle: DialGeometry.centreAngle(index)))
        }
    }

    /// The `glow` dot in the gap, under the menu bar glyph.
    private var tether: some View {
        Circle()
            .fill(DialColor.glow)
            .frame(width: 5, height: 5)
            .position(
                x: DialPath.centre.x + presentation.tetherOffset,
                y: DialPath.centre.y - DialGeometry.ringOuterRadius + 4
            )
    }

    private var well: some View {
        disc(radius: DialGeometry.ringInnerRadius - DialGeometry.wellInset)
    }

    /// The well sits at r 62, inside the ring's r 68 edge. In the references
    /// the 6pt between them shows the page, shaded by the ring's shadow. Over a
    /// real desktop it would show whatever is behind, so this disc fills it,
    /// under the ring so the shadow still falls on it.
    private var wellBacking: some View {
        disc(radius: DialGeometry.ringInnerRadius)
    }

    private func disc(radius: CGFloat) -> some View {
        Circle()
            .fill(DialColor.ringWell)
            .frame(width: radius * 2, height: radius * 2)
    }

    // MARK: - Mouse

    private func click(at location: CGPoint) {
        let dx = location.x - DialPath.centre.x
        let dy = location.y - DialPath.centre.y
        let radius = (dx * dx + dy * dy).squareRoot()
        if radius <= DialGeometry.knobRadius {
            onPress()
            return
        }
        guard radius >= DialGeometry.ringInnerRadius, radius <= DialGeometry.ringOuterRadius + DialGeometry.segmentLift else { return }
        var angle = atan2(dx, -dy) * 180 / .pi
        if angle < 0 { angle += 360 }
        let start = DialGeometry.ringGapDegrees / 2
        guard angle >= start, angle <= 360 - start else { return }
        let index = min(DialGeometry.segmentCount - 1, Int((angle - start) / DialGeometry.segmentDegrees))
        onSelect(model.ringOrder[index])
    }
}

/// One segment's icon: idle or active colour, a tick when it becomes selected,
/// and a staggered pop on summon.
private struct SegmentIcon: View {
    let mode: ModeID
    let isSelected: Bool
    /// Modes turned off in Settings stay on the ring, dimmed, and are skipped.
    let isEnabled: Bool
    let tick: Int
    let isShown: Bool
    let summonDelay: Double
    let reduceMotion: Bool

    var body: some View {
        DialIconView(icon: DialIcon(mode))
            .foregroundStyle(isSelected ? DialColor.iconActive : DialColor.iconIdle)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(reduceMotion ? nil : DialMotion.detent, value: isSelected)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : tick) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                // 100 → 118 → 100% over the 160ms detent, peaking at 45%.
                CubicKeyframe(1.18, duration: 0.072)
                SpringKeyframe(1.0, duration: 0.088, spring: .snappy)
            }
            .opacity(isShown || reduceMotion ? 1 : 0)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.4)
            .animation(summonAnimation, value: isShown)
    }

    private var summonAnimation: Animation? {
        if reduceMotion { return nil }
        // Icons arrive in turning order; they leave together.
        return isShown ? DialMotion.summon.delay(summonDelay) : DialMotion.dismiss
    }
}

/// The dial drops from the menu bar: from y −28 at 70% scale with a 6pt blur,
/// scaling from top centre. It folds back the same way, faster.
private struct SummonEffect: ViewModifier {
    let isShown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(isShown ? 1 : 0)
        } else {
            content
                .scaleEffect(isShown ? 1 : 0.7, anchor: .top)
                .offset(y: isShown ? 0 : -28)
                .blur(radius: isShown ? 0 : 6)
                .opacity(isShown ? 1 : 0)
                .animation(isShown ? DialMotion.summon : DialMotion.dismiss, value: isShown)
        }
    }
}

#Preview("Volume, dark") {
    DialPreview(selection: .volume)
        .preferredColorScheme(.dark)
}

#Preview("Mission Control, dark") {
    DialPreview(selection: .missionControl)
        .preferredColorScheme(.dark)
}

#Preview("Volume, light") {
    DialPreview(selection: .volume)
        .preferredColorScheme(.light)
}

/// A dial on the canvas ground, as in the reference screenshots.
struct DialPreview: View {
    let model: DialModel
    let presentation: DialPresentation

    init(selection: ModeID) {
        model = DialModel.preview(selecting: selection)
        presentation = DialPresentation()
        presentation.isShown = true
    }

    var body: some View {
        DialView(model: model, presentation: presentation)
            .padding(.vertical, 60)
            .padding(.horizontal, 80)
            .background(DialColor.canvas)
    }
}
