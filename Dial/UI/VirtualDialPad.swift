import AppKit
import SwiftUI

/// A floating, tactile on-screen controller replicating the physical CMF Buds Pro 2 Smart Dial.
/// Enables rotation via touch/mouse dragging, trackpad two-finger scrolling, and clicking the knob.
public struct VirtualDialPadView: View {
    @Bindable var model: DialModel
    @State private var dragAngle: Double = 0.0
    @State private var previousAngle: Double = 0.0
    @State private var isPressing: Bool = false
    @State private var accumulatedScroll: CGFloat = 0

    public init(model: DialModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            // Background glass container
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)

            VStack(spacing: 14) {
                // Header status
                HStack {
                    Circle()
                        .fill(model.activeMode != nil ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text("CMF DIALPAD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.phaseDescription.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Rotary Dial Body
                ZStack {
                    // Outer knurled rim
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.2),
                                    Color.black.opacity(0.4),
                                    Color.white.opacity(0.2),
                                    Color.black.opacity(0.4),
                                    Color.white.opacity(0.2)
                                ]),
                                center: .center
                            ),
                            lineWidth: 12
                        )
                        .frame(width: 154, height: 154)

                    // Dial face
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.22), Color(white: 0.12)],
                                center: .center,
                                startRadius: 10,
                                endRadius: 75
                            )
                        )
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

                    // Tick marks
                    ForEach(0..<24) { tick in
                        Rectangle()
                            .fill(Color.white.opacity(tick % 6 == 0 ? 0.7 : 0.25))
                            .frame(width: tick % 6 == 0 ? 2 : 1, height: tick % 6 == 0 ? 8 : 4)
                            .offset(y: -58)
                            .rotationEffect(.degrees(Double(tick) * (360.0 / 24.0)))
                    }

                    // Rotating indicator notch
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .offset(y: -46)
                        .rotationEffect(.degrees(model.knobAngle))

                    // Center tactile push button
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isPressing
                                    ? [Color(white: 0.15), Color(white: 0.25)]
                                    : [Color(white: 0.28), Color(white: 0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .scaleEffect(isPressing ? 0.94 : 1.0)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                    // Center label & icon
                    VStack(spacing: 2) {
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.orange)
                        Text(model.currentMode.shortLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 160, height: 160)
                // Rotary drag gesture
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let center = CGPoint(x: 80, y: 80)
                            let currentPoint = value.location
                            let dx = currentPoint.x - center.x
                            let dy = currentPoint.y - center.y
                            let currentAngle = atan2(dy, dx) * 180 / .pi

                            if previousAngle != 0 {
                                var delta = currentAngle - previousAngle
                                // Handle wraparound across +/- 180
                                if delta > 180 { delta -= 360 }
                                else if delta < -180 { delta += 360 }

                                dragAngle += delta
                                if abs(dragAngle) >= 15.0 {
                                    let steps = Int(dragAngle / 15.0)
                                    if steps != 0 {
                                        DialAudio.playClick()
                                        model.handle(.turn(steps), from: "virtualDial")
                                        dragAngle -= Double(steps) * 15.0
                                    }
                                }
                            }
                            previousAngle = currentAngle
                        }
                        .onEnded { _ in
                            previousAngle = 0.0
                            dragAngle = 0.0
                        }
                )
                // Center button tap & double-tap
                .onTapGesture(count: 2) {
                    DialAudio.playSummon()
                    model.handle(.doublePress, from: "virtualDial")
                }
                .onTapGesture(count: 1) {
                    DialAudio.playPress()
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressing = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isPressing = false
                        model.handle(.press, from: "virtualDial")
                    }
                }

                // Instructions bar
                HStack(spacing: 8) {
                    Text("Drag to rotate")
                        .font(.system(size: 9, weight: .medium))
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Click: Press")
                        .font(.system(size: 9, weight: .medium))
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Double-Click: Menu")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 220, height: 260)
    }
}

/// Floating panel window for the Virtual DialPad.
public final class VirtualDialPadPanel: NSPanel {
    public static let shared = VirtualDialPadPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 200, y: 200, width: 220, height: 260),
            styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
    }

    public func configure(with model: DialModel) {
        let hosting = NSHostingView(rootView: VirtualDialPadView(model: model))
        self.contentView = hosting
    }

    public func toggleVisibility() {
        if isVisible {
            orderOut(nil)
        } else {
            makeKeyAndOrderFront(nil)
        }
    }
}
