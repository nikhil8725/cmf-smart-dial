import AppKit
import AudioToolbox

/// Provides mechanical audio and haptic feedback for rotary detent clicks and presses.
public enum DialAudio {
    /// Global toggle for sound effects
    public static var isEnabled: Bool = true

    /// Plays subtle tactile click when advancing a detent
    public static func playClick() {
        guard isEnabled else { return }
        // AudioServicesPlaySystemSound 1104 is macOS's built-in tick/click
        AudioServicesPlaySystemSound(1104)
    }

    /// Plays pop sound when a mode or button is pressed
    public static func playPress() {
        guard isEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    /// Plays chime when radial wheel is summoned or dismissed
    public static func playSummon() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }
}
