import Observation
import SwiftUI

/// What the HUD panel is showing. Kept separate from the model so the last
/// content stays on screen while the pill fades out.
@Observable
final class HUDPresentation {
    var content: HUDContent?
    var isShown = false
    /// Bumped on each update, to nudge the value.
    var revision = 0
}

/// The mode HUD pill (DESIGN.md, "HUD pill"; components/ModeHUD.md): icon,
/// label, then a meter for levels and a value.
struct HUDView: View {
    let presentation: HUDPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Meter size from DESIGN.md.
    private static let meterSize = CGSize(width: 72, height: 4)
    /// Inner padding from the reference (0 14 0 11), so the icon sits optically centred.
    private static let leadingPadding: CGFloat = 11
    private static let trailingPadding: CGFloat = 14
    private static let height: CGFloat = 34

    var body: some View {
        Group {
            if let content = presentation.content {
                pill(content)
            }
        }
        .scaleEffect(presentation.isShown || reduceMotion ? 1 : 0.9, anchor: .top)
        .offset(y: presentation.isShown || reduceMotion ? 0 : -8)
        .opacity(presentation.isShown ? 1 : 0)
        .animation(reduceMotion ? nil : (presentation.isShown ? DialMotion.hud : DialMotion.dismiss), value: presentation.isShown)
    }

    private func pill(_ content: HUDContent) -> some View {
        HStack(spacing: DialSpace.s2) {
            DialIconView(icon: DialIcon(content.mode), size: 16)
            Text(content.mode.label)
                .font(DialFont.hudLabel)
                .fixedSize()
            if let level = content.reading.level {
                meter(level)
            }
            value(content.reading.text)
        }
        .foregroundStyle(DialColor.ink)
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .frame(height: Self.height)
        .background(Capsule().fill(DialColor.card))
        .overlay(Capsule().strokeBorder(DialColor.cardBorder, lineWidth: 1))
        .compositingGroup()
        .dialShadow(.card)
        .accessibilityElement(children: .combine)
    }

    private func meter(_ level: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(DialColor.hairline)
            Capsule()
                .fill(DialColor.ink)
                .frame(width: Self.meterSize.width * min(max(level, 0), 1))
                .animation(reduceMotion ? nil : DialMotion.detent, value: level)
        }
        .frame(width: Self.meterSize.width, height: Self.meterSize.height)
    }

    /// Nudges up 2pt and back, brightening to `ink`, so a change you can't
    /// see elsewhere (volume) still registers.
    private func value(_ text: String) -> some View {
        Text(text)
            .font(DialFont.hudValue)
            .fixedSize()
            .frame(minWidth: 24, alignment: .trailing)
            .keyframeAnimator(initialValue: ValueBump(), trigger: reduceMotion ? 0 : presentation.revision) { content, bump in
                content
                    .foregroundStyle(DialColor.inkMuted)
                    .overlay(content.foregroundStyle(DialColor.ink).opacity(bump.ink))
                    .offset(y: bump.y)
            } keyframes: { _ in
                // 180ms on the spring curve, peaking at 45%.
                KeyframeTrack(\.y) {
                    CubicKeyframe(-2, duration: 0.081)
                    SpringKeyframe(0, duration: 0.099, spring: .snappy)
                }
                KeyframeTrack(\.ink) {
                    CubicKeyframe(1, duration: 0.081)
                    CubicKeyframe(0, duration: 0.099)
                }
            }
    }
}

private struct ValueBump {
    var y: CGFloat = 0
    var ink: Double = 0
}

#if DEBUG && canImport(PreviewsMacros)
#Preview("Volume, dark") {
    HUDPreview(content: HUDContent(mode: .volume, reading: HUDReading(level: 0.68, text: "68"), afterChoose: false))
        .preferredColorScheme(.dark)
}

#Preview("Tabs, light") {
    HUDPreview(content: HUDContent(mode: .tabs, reading: HUDReading(level: nil, text: "Next ×2"), afterChoose: false))
        .preferredColorScheme(.light)
}
#endif

/// A HUD on the canvas ground, as in the reference screenshots.
struct HUDPreview: View {
    let presentation: HUDPresentation

    init(content: HUDContent) {
        presentation = HUDPresentation()
        presentation.content = content
        presentation.isShown = true
    }

    var body: some View {
        presentationView
            .padding(40)
            .background(DialColor.canvas)
    }

    var presentationView: some View {
        HUDView(presentation: presentation)
    }
}
