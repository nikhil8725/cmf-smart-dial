import AppKit
import Observation
import SwiftUI

/// The menu bar item: the ring glyph and the current mode's name, with the
/// `cardActive` highlight while the dial is open (DESIGN.md, "The menu bar
/// item and panels"). Click opens or closes the dial; right-click or
/// control-click shows the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Horizontal padding inside the highlight, and the glyph's size.
    private static let padding: CGFloat = 8
    private static let glyphSize: CGFloat = 15

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: DialModel
    private let encoder: VolumeEncoder
    private let presentation: DialPresentation
    private let settings: SettingsStore
    /// Shown only with testing tools on.
    private var testingItems: [NSMenuItem] = []
    private var label: NSHostingView<StatusItemLabel>?
    private let menu = NSMenu()

    var onShowDebugLog: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onShowSetupGuide: (() -> Void)?
    var onReclaimMediaButtons: (() -> Void)?

    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let budsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(model: DialModel, encoder: VolumeEncoder, presentation: DialPresentation, settings: SettingsStore) {
        self.model = model
        self.encoder = encoder
        self.presentation = presentation
        self.settings = settings
        super.init()
        buildButton()
        buildMenu()
        trackLabelWidth()
    }

    /// Where the dial should hang from.
    var anchor: DialAnchor? {
        guard let button = item.button, let window = button.window, let screen = window.screen else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let glyphX: CGFloat
        if let label {
            glyphX = frame.minX + label.frame.minX + Self.padding + Self.glyphSize / 2
        } else {
            glyphX = frame.midX
        }
        return DialAnchor(glyphCentreX: glyphX, menuBarBottom: window.frame.minY, screen: screen)
    }

    private func buildButton() {
        guard let button = item.button else { return }
        let hosting = PassThroughHostingView(rootView: StatusItemLabel(model: model, presentation: presentation))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        ])
        label = hosting
        button.setAccessibilityLabel("Dial")
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// The item's width follows the label.
    private func trackLabelWidth() {
        withObservationTracking {
            _ = model.currentMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateLength()
                self?.trackLabelWidth()
            }
        }
        updateLength()
    }

    private func updateLength() {
        guard let label else { return }
        label.invalidateIntrinsicContentSize()
        item.length = label.fittingSize.width
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            model.handle(.doublePress, from: "click")
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        stateItem.isEnabled = false
        budsItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(budsItem)
        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibilitySettings)
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let virtualDial = NSMenuItem(title: "Virtual DialPad Controller…", action: #selector(toggleVirtualDialPad), keyEquivalent: "v")
        virtualDial.target = self
        menu.addItem(virtualDial)
        let guide = NSMenuItem(title: "Setup Guide…", action: #selector(showSetupGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)
        menu.addItem(.separator())

        let debug = NSMenuItem(title: "Show Debug Log", action: #selector(showDebugLog), keyEquivalent: "l")
        debug.target = self
        menu.addItem(debug)
        testingItems.append(debug)
        let reclaim = NSMenuItem(title: "Reclaim Media Buttons", action: #selector(reclaimMediaButtons), keyEquivalent: "")
        reclaim.target = self
        reclaim.toolTip = "Use this if another app started playing and the dial press stopped reaching Dial."
        menu.addItem(reclaim)

        menu.addItem(.separator())
        let hotkeys = NSMenuItem(title: "Simulate: ⌃⌥← → turn · ⌃⌥Space press · ⌃⌥D double press", action: nil, keyEquivalent: "")
        hotkeys.isEnabled = false
        menu.addItem(hotkeys)
        testingItems.append(hotkeys)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Dial", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Dial", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        testingItems.forEach { $0.isHidden = !settings.testingTools }
        stateItem.title = "State: \(model.phaseDescription)"
        if let buds = encoder.deviceLabel {
            budsItem.title = "Buds: \(buds) · volume \(model.shouldPark ? "parked" : "pass-through")"
        } else {
            budsItem.title = "Buds: not the sound output, turns are off"
        }
        if Permissions.isAccessibilityTrusted {
            accessibilityItem.title = "Accessibility: on"
            accessibilityItem.isEnabled = false
        } else {
            accessibilityItem.title = "Accessibility: off — Open Settings…"
            accessibilityItem.isEnabled = true
        }
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func toggleVirtualDialPad() {
        VirtualDialPadPanel.shared.configure(with: model)
        VirtualDialPadPanel.shared.toggleVisibility()
    }

    @objc private func showSetupGuide() {
        onShowSetupGuide?()
    }

    @objc private func showDebugLog() {
        onShowDebugLog?()
    }

    @objc private func reclaimMediaButtons() {
        onReclaimMediaButtons?()
    }
}

/// Draws inside the status button but leaves its clicks to the button.
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Ring glyph and mode name in `hudLabel`, on a `cardActive` highlight while
/// the dial is open.
struct StatusItemLabel: View {
    let model: DialModel
    let presentation: DialPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            DialIconView(icon: .ring, size: 15)
            ZStack {
                Text(model.currentMode.label)
                    .font(DialFont.hudLabel)
                    .fixedSize()
                    .id(model.currentMode)
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 4)),
                        removal: .identity
                    ))
            }
            .animation(reduceMotion ? nil : DialMotion.labelSwap, value: model.currentMode)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: DialRadius.sm)
                .fill(DialColor.cardActive)
                .opacity(presentation.isShown ? 1 : 0)
                // The 160ms highlight from motion.md; no token covers it.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: presentation.isShown)
        )
    }
}
