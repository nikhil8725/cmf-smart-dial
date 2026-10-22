import AppKit
import Carbon.HIToolbox
import Foundation

/// Navigation and scrolling engine:
/// Supports vertical scroll, arrow keys (↓/↑), tab navigation (⇥/⇧⇥), and sideways scroll.
final class ScrollMode: Mode {
    let id = ModeID.scroll
    var onReadingChange: (() -> Void)?

    private static let linesPerDetent = 3

    enum SubMode: Int, CaseIterable {
        case vertical
        case arrowKeys
        case tabNavigation
        case horizontal

        var label: String {
            switch self {
            case .vertical: return "Scroll (Vertical)"
            case .arrowKeys: return "Arrow Keys (↓ / ↑)"
            case .tabNavigation: return "Tab Navigate (⇥ / ⇧⇥)"
            case .horizontal: return "Sideways Scroll (← / →)"
            }
        }
    }

    private var subMode: SubMode = .vertical
    private var tally = StepTally()

    var reading: HUDReading {
        guard tally.net != 0 else {
            return HUDReading(level: nil, text: subMode.label)
        }
        switch subMode {
        case .vertical:
            let lines = abs(tally.net) * Self.linesPerDetent
            let arrow = tally.net > 0 ? "↓" : "↑"
            return HUDReading(level: nil, text: "\(arrow) \(lines) lines")
        case .horizontal:
            let lines = abs(tally.net) * Self.linesPerDetent
            let arrow = tally.net > 0 ? "→" : "←"
            return HUDReading(level: nil, text: "\(arrow) \(lines) lines")
        case .arrowKeys:
            let arrow = tally.net > 0 ? "Down ↓" : "Up ↑"
            return HUDReading(level: nil, text: "\(arrow) ×\(abs(tally.net))")
        case .tabNavigation:
            let tab = tally.net > 0 ? "Tab ⇥" : "Shift+Tab ⇧⇥"
            return HUDReading(level: nil, text: "\(tab) ×\(abs(tally.net))")
        }
    }

    func turn(_ steps: Int) {
        tally.add(steps)
        switch subMode {
        case .vertical:
            ScrollEmitter.scroll(lines: steps * Self.linesPerDetent, horizontal: false)
        case .horizontal:
            ScrollEmitter.scroll(lines: steps * Self.linesPerDetent, horizontal: true)
        case .arrowKeys:
            let forward = KeyEmitter.Shortcut(kVK_DownArrow)
            let backward = KeyEmitter.Shortcut(kVK_UpArrow)
            KeyEmitter.post(steps: steps, forward: forward, backward: backward)
        case .tabNavigation:
            let forward = KeyEmitter.Shortcut(kVK_Tab)
            let backward = KeyEmitter.Shortcut(kVK_Tab, [.maskShift])
            KeyEmitter.post(steps: steps, forward: forward, backward: backward)
        }
    }

    func press() -> String {
        let nextIndex = (subMode.rawValue + 1) % SubMode.allCases.count
        subMode = SubMode(rawValue: nextIndex) ?? .vertical
        tally = StepTally()
        return subMode.label
    }
}
