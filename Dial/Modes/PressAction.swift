import AppKit
import Carbon.HIToolbox

/// What a press does in a mode. Each mode's first option is its own action,
/// which the mode performs; the rest are general actions done here. The brand
/// book calls the defaults suggestions, changeable per mode in Settings.
enum PressAction: String, CaseIterable, Codable {
    case playPause, mute, nightShift, openApp, bringForward, showDesktop, missionControl
    case newTab, closeTab, reopenTab, sideways, scrollToTop, pressReturn, pressSpace, save, startShow, blackScreen
    case nothing

    /// Shown in Settings and, after a press, in the HUD.
    var label: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .mute: return "Mute"
        case .nightShift: return "Night Shift"
        case .openApp: return "Open the app"
        case .bringForward: return "Bring window forward"
        case .showDesktop: return "Show desktop"
        case .missionControl: return "Mission Control"
        case .newTab: return "New tab"
        case .closeTab: return "Close tab"
        case .reopenTab: return "Reopen closed tab"
        case .sideways: return "Switch Mode (Scroll / Arrow / Tab)"
        case .scrollToTop: return "Scroll to top"
        case .pressReturn: return "Press Return / Enter (↩)"
        case .pressSpace: return "Press Space"
        case .save: return "Save"
        case .startShow: return "Start / end show"
        case .blackScreen: return "Black screen"
        case .nothing: return "Nothing"
        }
    }

    /// Performs a general action and returns its HUD name. The mode's own
    /// action (each mode's first option) is never sent here.
    func perform() -> String {
        switch self {
        case .mute:
            SystemControls.postMediaKey(.mute)
        case .missionControl:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"), configuration: NSWorkspace.OpenConfiguration())
        case .closeTab:
            KeyEmitter.post(KeyEmitter.Shortcut(kVK_ANSI_W, .maskCommand))
        case .reopenTab:
            KeyEmitter.post(KeyEmitter.Shortcut(kVK_ANSI_T, [.maskCommand, .maskShift]))
        case .scrollToTop:
            KeyEmitter.post(KeyEmitter.Shortcut(kVK_UpArrow, .maskCommand))
        case .pressReturn:
            KeyEmitter.post(KeyEmitter.Shortcut(kVK_Return))
        case .pressSpace:
            KeyEmitter.post(KeyEmitter.Shortcut(kVK_Space))
        case .blackScreen:
            // Keynote, PowerPoint and Google Slides all black the screen on B.
            KeyEmitter.post(KeyEmitter.Shortcut(kVK_ANSI_B))
        default:
            break
        }
        return label
    }
}

extension ModeID {
    /// The press actions Settings offers; the first is the mode's own and the default.
    var pressOptions: [PressAction] {
        switch self {
        case .volume: return [.playPause, .mute, .nothing]
        case .brightness: return [.nightShift, .nothing]
        case .apps: return [.openApp]
        case .missionControl: return [.bringForward]
        case .desktops: return [.showDesktop, .missionControl, .nothing]
        case .tabs: return [.newTab, .closeTab, .reopenTab, .nothing]
        case .scroll: return [.sideways, .pressReturn, .pressSpace, .scrollToTop, .nothing]
        case .undoRedo: return [.save, .nothing]
        case .slides: return [.startShow, .blackScreen, .nothing]
        }
    }
}
