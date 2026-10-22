import Foundation
import Observation

/// The one state machine. Input sources feed it events; views only read it.
///
///   rest ──double press──▶ picking ──press──▶ inMode(m)
///                            ▲  │                │
///                            │  └─double press / idle─▶ back to where it came from
///                            └──────double press─────┘
///
/// At rest and in Volume mode the dial behaves like plain earbuds: turns move
/// the volume and a press goes to the music app.
@Observable
final class DialModel {
    enum Phase: Equatable {
        case rest
        case picking
        case inMode(ModeID)
    }

    private(set) var phase: Phase = .rest

    /// Every mode in ring order; segment i of the ring is `ringOrder[i]`.
    private(set) var ringOrder: [ModeID]
    /// The modes the selection moves through, in ring order.
    private(set) var modes: [ModeID]
    /// The settings' press choices (read through `pressAction(for:)`).
    @ObservationIgnored private var pressActions: DialSettings

    /// Events from the real buds, for onboarding's "try it" step.
    private(set) var budsEvents = BudsEventCounts()

    private(set) var selectedMode: ModeID

    /// The highlight's angle in degrees, clockwise from 12 o'clock. A running
    /// total, never wrapped: one detent adds a segment, and a step across the
    /// gap adds a segment plus the gap (DESIGN.md, "Angles must accumulate").
    private(set) var highlightAngle: Double
    /// Where the knob's 0° pointer mark points. Follows the highlight while
    /// picking; turns `knobDetentDegrees` per detent inside a mode.
    private(set) var knobAngle: Double

    /// Bumped on every selection change and every press while picking, so
    /// views can run one-shot animations (icon tick, label swap, press pulse).
    private(set) var detentCount = 0
    private(set) var pressCount = 0

    /// What the HUD pill shows; nil hides it. `hudRevision` bumps on every
    /// update so the HUD restarts its linger and nudges the value.
    private(set) var hud: HUDContent?
    private(set) var hudRevision = 0

    /// Apps mode keeps the dial out with a fan of app cards until a press,
    /// a double press or the idle timeout (components/AppFan.md).
    private(set) var isFanOpen = false

    /// When the latest detent arrived and the gap before it, for fast spin.
    private(set) var lastDetentAt: Date?
    private(set) var lastDetentInterval: TimeInterval?

    /// The mode in effect, shown in the menu bar: the active one, Volume at
    /// rest (where the dial is a volume knob), and while picking, whichever
    /// of those the pick started from.
    var currentMode: ModeID {
        switch phase {
        case .inMode(let mode): return mode
        case .rest: return .volume
        case .picking:
            if case .inMode(let mode) = phaseBeforePicking { return mode }
            return .volume
        }
    }

    /// Where a cancelled pick returns to.
    private var phaseBeforePicking: Phase = .rest
    @ObservationIgnored private var handlers: [ModeID: Mode] = [:]
    @ObservationIgnored private var idleTimer: Timer?

    /// Told whenever the encoder should start or stop parking the volume.
    @ObservationIgnored var onParkingChange: ((Bool) -> Void)?
    /// Hands a press to the music app (rest and Volume mode).
    @ObservationIgnored var passPressToMediaApp: (() -> Void)?

    init(settings: DialSettings) {
        let enabled = settings.enabledModes
        ringOrder = settings.order
        modes = enabled
        pressActions = settings
        selectedMode = enabled[0]
        let start = DialGeometry.centreAngle(settings.order.firstIndex(of: enabled[0]) ?? 0)
        highlightAngle = start
        knobAngle = start
    }

    /// Takes new settings live: segment order, which modes are on, press actions.
    func apply(_ settings: DialSettings) {
        ringOrder = settings.order
        modes = settings.enabledModes
        pressActions = settings
        if !modes.contains(selectedMode) { selectedMode = modes[0] }
        // The selected mode may have moved: point at its segment again, the short way round.
        let target = DialGeometry.centreAngle(segmentIndex(of: selectedMode))
        highlightAngle = target + 360 * ((highlightAngle - target) / 360).rounded()
        if phase == .picking { knobAngle = highlightAngle }
        if let active = activeMode, !modes.contains(active) {
            log("state", "\(active.label) was turned off in Settings")
            handlers[active]?.deactivate()
            setPhase(.rest)
        }
    }

    func register(_ mode: Mode) {
        handlers[mode.id] = mode
        mode.onReadingChange = { [weak self, weak mode] in
            guard let self, let mode, let hud = self.hud, hud.mode == mode.id else { return }
            self.hud = HUDContent(mode: mode.id, reading: mode.reading, afterChoose: false, sticky: mode.hudIsSticky)
        }
    }

    // MARK: - Derived state

    var activeMode: ModeID? {
        if case .inMode(let mode) = phase { return mode }
        return nil
    }

    var isPicking: Bool { phase == .picking }

    var isFastSpin: Bool {
        guard let interval = lastDetentInterval else { return false }
        return interval < DialMotion.fastStepThreshold
    }

    /// Parked everywhere except rest and Volume mode, where the dial is a volume knob.
    var shouldPark: Bool {
        switch phase {
        case .rest: return false
        case .picking: return true
        case .inMode(let mode): return mode != .volume
        }
    }

    var phaseDescription: String {
        switch phase {
        case .rest: return "rest"
        case .picking: return "picking (\(selectedMode.label))"
        case .inMode(let mode): return "in \(mode.label)"
        }
    }

    func segmentIndex(of mode: ModeID) -> Int {
        ringOrder.firstIndex(of: mode) ?? 0
    }

    // MARK: - Events

    func handle(_ event: DialEvent, from source: String) {
        log("event", "\(event) from \(source)  [state: \(phaseDescription)]")
        if source == "volume" || source == "remote" {
            budsEvents.record(event)
        }
        switch (phase, event) {
        case (.rest, .turn):
            // The encoder isn't parking, so the volume already moved.
            showHUD(.volume)
        case (.rest, .press):
            // At rest the dial is a volume knob, so Volume's press action applies.
            let action = pressActions.pressAction(for: .volume)
            switch action {
            case .playPause:
                log("state", "press at rest → music app")
                passPressToMediaApp?()
                showHUD(.volume, text: action.label)
            case .nothing:
                log("state", "press at rest: set to do nothing")
            default:
                guard Permissions.ensureAccessibility(reason: action.label.lowercased()) else { return }
                showHUD(.volume, text: action.perform())
            }
        case (.rest, .doublePress), (.inMode, .doublePress):
            beginPicking()

        case (.picking, .turn(let steps)):
            recordDetent()
            moveSelection(by: steps)
            log("state", "selection → \(selectedMode.label) (highlight \(Int(highlightAngle))°)")
            restartIdleTimer()
        case (.picking, .press):
            pressCount += 1
            choose(selectedMode)
        case (.picking, .doublePress):
            endPicking(reason: "double press")

        case (.inMode(.apps), .turn(let steps)):
            recordDetent()
            knobAngle += Double(steps) * DialGeometry.knobDetentDegrees
            if !isFanOpen { openFan() }
            handlers[.apps]?.turn(steps)
            restartIdleTimer()
        case (.inMode(.apps), .press):
            guard let handler = handlers[.apps], hasPermission(for: handler) else { return }
            pressCount += 1
            idleTimer?.invalidate()
            let action = handler.press()
            log("mode", "Apps: press → \(action)")
            // The card flashes, then the fan and dial fold up.
            isFanOpen = false
            showHUD(.apps, text: action, afterChoose: true)
            choose(.scroll)

        case (.inMode(let mode), .turn(let steps)):
            recordDetent()
            knobAngle += Double(steps) * DialGeometry.knobDetentDegrees
            guard let handler = handlers[mode], hasPermission(for: handler) else { return }
            handler.turn(steps)
            showHUD(mode)
        case (.inMode(let mode), .press):
            guard let handler = handlers[mode], hasPermission(for: handler) else { return }
            let choice = pressActions.pressAction(for: mode)
            if choice == .nothing {
                log("mode", "\(mode.label): press set to do nothing")
                return
            }
            // The mode's own action is its first option; the rest are general.
            let name = choice == mode.pressOptions[0] ? handler.press() : choice.perform()
            log("mode", "\(mode.label): press → \(name)")
            showHUD(mode, text: name)
        }
    }

    // MARK: - HUD

    private func showHUD(_ mode: ModeID, text: String? = nil, afterChoose: Bool = false) {
        var reading = handlers[mode]?.reading ?? .empty
        if let text { reading.text = text }
        hud = HUDContent(mode: mode, reading: reading, afterChoose: afterChoose, sticky: handlers[mode]?.hudIsSticky ?? false)
        hudRevision += 1
    }

    /// Modes that post events need Accessibility; without it, ask once and say so in the HUD.
    private func hasPermission(for handler: Mode) -> Bool {
        guard handler.needsAccessibility, !Permissions.isAccessibilityTrusted else { return true }
        Permissions.requestAccessibility(reason: "use \(handler.label)")
        showHUD(handler.id, text: "Needs Accessibility")
        return false
    }

    /// Mouse: jump straight to a segment while picking.
    func select(_ mode: ModeID) {
        guard phase == .picking, mode != selectedMode, let target = modes.firstIndex(of: mode) else { return }
        moveSelection(toIndex: target)
        log("state", "selection → \(selectedMode.label) (clicked)")
        restartIdleTimer()
    }

    // MARK: - Selection

    private func moveSelection(by steps: Int) {
        let direction = steps > 0 ? 1 : -1
        for _ in 0..<abs(steps) {
            let index = modes.firstIndex(of: selectedMode) ?? 0
            step(to: modes[(index + direction + modes.count) % modes.count], direction: direction)
        }
        knobAngle = highlightAngle
        detentCount += 1
    }

    /// Moves the shorter way round, one step at a time, so the angle stays continuous.
    fileprivate func moveSelection(toIndex target: Int) {
        let current = modes.firstIndex(of: selectedMode) ?? 0
        let forward = (target - current + modes.count) % modes.count
        guard forward != 0 else { return }
        if forward <= modes.count / 2 {
            moveSelection(by: forward)
        } else {
            moveSelection(by: forward - modes.count)
        }
    }

    private func step(to next: ModeID, direction: Int) {
        let from = segmentIndex(of: selectedMode)
        let to = segmentIndex(of: next)
        let count = ringOrder.count
        let segments = direction > 0 ? (to - from + count) % count : (from - to + count) % count
        let crossesGap = direction > 0 ? to <= from : to >= from
        let degrees = Double(segments) * DialGeometry.segmentDegrees + (crossesGap ? DialGeometry.ringGapDegrees : 0)
        highlightAngle += Double(direction) * degrees
        selectedMode = next
    }

    // MARK: - Transitions

    private func beginPicking() {
        DialAudio.playSummon()
        // Double press closes Mission Control without changing anything.
        if activeMode == .missionControl { handlers[.missionControl]?.deactivate() }
        phaseBeforePicking = phase
        isFanOpen = false
        if let target = modes.firstIndex(of: activeMode ?? .volume) {
            moveSelection(toIndex: target)
        }
        // The knob may have turned inside a mode; bring it back to the
        // highlight the short way round.
        knobAngle = highlightAngle + 360 * ((knobAngle - highlightAngle) / 360).rounded()
        setPhase(.picking)
        hud = nil
        restartIdleTimer()
    }

    private func choose(_ mode: ModeID) {
        idleTimer?.invalidate()
        let previous: ModeID? = {
            if case .inMode(let old) = phaseBeforePicking { return old }
            return nil
        }()
        setPhase(.inMode(mode))
        if let previous, previous != mode { handlers[previous]?.deactivate() }
        // Even when it's the same mode again: choosing Mission Control reopens it.
        handlers[mode]?.activate()
        if mode == .apps {
            // The dial stays out and the fan opens; no HUD under it.
            openFan()
            restartIdleTimer()
        } else {
            showHUD(mode, afterChoose: true)
        }
    }

    private func openFan() {
        (handlers[.apps] as? AppsMode)?.refresh()
        isFanOpen = true
        log("state", "app fan open")
    }

    private func endPicking(reason: String) {
        idleTimer?.invalidate()
        log("state", "picking closed by \(reason)")
        setPhase(phaseBeforePicking)
    }

    private func setPhase(_ newPhase: Phase) {
        let oldPark = shouldPark
        let oldDescription = phaseDescription
        phase = newPhase
        log("state", "\(oldDescription) → \(phaseDescription)")
        if shouldPark != oldPark {
            onParkingChange?(shouldPark)
        }
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: DialMotion.idleDismiss, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.phase == .picking {
                self.endPicking(reason: "\(Int(DialMotion.idleDismiss))s idle")
            } else if self.isFanOpen {
                self.isFanOpen = false
                log("state", "app fan closed by \(Int(DialMotion.idleDismiss))s idle")
            }
        }
    }

    private func recordDetent() {
        DialAudio.playClick()
        let now = Date()
        lastDetentInterval = lastDetentAt.map { now.timeIntervalSince($0) }
        lastDetentAt = now
    }
}

extension DialModel {
    /// A model already picking, with `mode` selected, for previews and snapshots.
    static func preview(selecting mode: ModeID) -> DialModel {
        let model = DialModel(settings: DialSettings(order: ModeID.allCases, disabled: []))
        model.phase = .picking
        if let target = model.modes.firstIndex(of: mode) {
            model.moveSelection(toIndex: target)
        }
        return model
    }
}

/// The HUD pill's content: which mode, and its meter and value.
struct HUDContent: Equatable {
    let mode: ModeID
    let reading: HUDReading
    /// Shown after the dial folds up, rather than at once.
    let afterChoose: Bool
    /// Stays up at the bottom of the screen until this turns false.
    var sticky = false
}

extension DialModel {
    /// A model in Apps mode with the fan open, for snapshots.
    static func previewFan(apps: AppsMode) -> DialModel {
        let model = preview(selecting: .apps)
        model.register(apps)
        model.phase = .inMode(.apps)
        model.isFanOpen = true
        return model
    }
}

/// How many of each gesture have arrived from the buds since launch.
struct BudsEventCounts: Equatable {
    private(set) var turns = 0
    private(set) var presses = 0
    private(set) var doublePresses = 0

    mutating func record(_ event: DialEvent) {
        switch event {
        case .turn: turns += 1
        case .press: presses += 1
        case .doublePress: doublePresses += 1
        }
    }
}
