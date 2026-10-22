# CMF Smart Dial (Dial Pro)

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange.svg)](https://swift.org)
[![Hardware](https://img.shields.io/badge/Hardware-CMF%20Buds%20Pro%202-red.svg)](https://cmf.tech)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Turn the physical Smart Dial on a CMF Buds Pro 2 case into an interactive radial control surface and tactile macro controller for your Mac.**

---

## 🌟 What is CMF Smart Dial?

The **Nothing CMF Buds Pro 2** charging case features a physical rotary dial and button. This project bridges that hardware to macOS, turning it into a dedicated **radial desktop controller** (like a Microsoft Surface Dial, Contour Shuttle, or Loupedeck) for your menu bar.

### Core Experience:
- 🔘 **Double-press the case dial:** A floating radial wheel of 9 control modes drops smoothly from your menu bar.
- 🎛️ **Turn the dial:** The knob turns with mechanical audio click feedback to select a mode.
- 👆 **Single press:** Locks in the mode.
- 🔄 **Turn freely:** From then on, every physical rotation drives that mode (volume, brightness, browser tabs, spaces, scrubbing open apps, etc.) until your next double press!

---

## 🚀 Key Features & Enhancements

### 1. 🎛️ Nine Native Desktop Control Modes
- **Volume:** Adjust output volume with a live on-screen level meter HUD.
- **Brightness:** Smooth hardware display brightness steps.
- **Apps (Card Fan):** Fans out your running app windows across the screen like a physical card deck, letting you scrub and switch instantly.
- **Mission Control:** Scrub open windows or trigger Mission Control views.
- **Desktops / Spaces:** Flick between macOS virtual desktops smoothly.
- **Browser Tabs:** Turn to scrub through browser tabs in Chrome, Safari, Brave, or Arc.
- **Canvas & Document Scroll:** Smooth vertical scrolling through documents, timelines, or web pages.
- **Undo / Redo:** Turn counter-clockwise to Undo (`⌘Z`) or clockwise to Redo (`⇧⌘Z`) with a live multiplier tally (`Undo ×4`).
- **Presentation Slides:** Advance or rewind slides in Keynote, PowerPoint, or Google Slides.

---

### 2. 🖱️ Interactive Virtual DialPad Controller (New!)
Don't have your earbuds nearby or currently charging them in your ears?
- Use the built-in **Virtual DialPad**: a floating circular controller you can keep on your desktop.
- **Drag with mouse or trackpad** around the dial ring to rotate with fluid physical inertia.
- **Two-finger trackpad / mouse scroll** directly over the dial.
- **Click center knob** to single-press, **double-click** to toggle the radial menu!

---

### 3. 🔊 Tactile Audio & Haptic Detent Clicks (New!)
- Physical rotary encoders rely on tactile notches (detents). CMF Smart Dial plays crisp, subtle mechanical click sounds on every detent turn so you feel the feedback without needing to stare at the screen.

---

### 4. ⚙️ Automation & Power-User Companion
Includes a standalone **Automation Companion Engine** (`AutomationCompanion/`) for power users who want the dial to trigger:
- Custom Shell scripts and CLI commands
- HTTP/REST API webhooks
- Dark Mode and audio toggles
- Background `launchd` service integration

---

## 🎧 How the CMF Hardware Talks to macOS

The dial on the CMF Buds Pro 2 case communicates with the earbuds, which in turn send standard Bluetooth headphone commands to macOS:

| Physical Case Gesture | Arrives on macOS as | What CMF Smart Dial Does |
| :--- | :--- | :--- |
| **Rotate Dial** | Bluetooth volume step | CoreAudio listener tracks direction (+/-) and resets volume to midpoint |
| **Single Press** | `Play / Pause` media key | Selects mode or triggers mode-specific action |
| **Double Press** | `Next Track` media key | Opens / closes the menu bar radial wheel |

> **⚠️ CRITICAL REQUIREMENT:**
> Keep the **case lid closed**! The CMF Buds Pro 2 dial only sends wireless commands when the case lid is completely shut.

---

## 📦 Installation & Setup

### 1. Configure Gestures in Nothing X Mobile App
1. Open the **Nothing X** app on your phone.
2. Go to **Smart Dial settings** for your CMF Buds Pro 2:
   - **Rotate:** Set to **Volume**
   - **Single Press:** Set to **Play/Pause**
   - **Double Press:** Set to **Next Track**

### 2. Connect to your Mac
1. Pair your CMF Buds Pro 2 with your Mac via Bluetooth.
2. Select them as your active Sound Output in **Control Centre → Sound**.
3. Close the charging case lid.

### 3. Download & Run the App
Download `Dial-1.0.dmg` from [Releases](https://github.com/nikhil8725/cmf-smart-dial/releases) (or build from source below), drag **Dial.app** into `/Applications`, and remove quarantine:
```bash
xattr -dr com.apple.quarantine /Applications/Dial.app
open /Applications/Dial.app
```

### 4. Accessibility Permissions
Open **System Settings → Privacy & Security → Accessibility** and ensure **Dial** is enabled. This allows the app to send simulated keypresses (such as `⌘Tab`, `⌘Z`, and arrow keys).

---

## ⌨️ Built-in Testing Shortcuts (No Buds Required)

You can test and control the dial entirely from your keyboard:
- `⌃⌥←` : Turn Left
- `⌃⌥→` : Turn Right
- `⌃⌥Space` : Press Knob
- `⌃⌥D` : Double Press (Summon / Dismiss Radial Wheel)

---

## 🛠️ Building from Source

Requirements: macOS 14+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
# 1. Clone repository
git clone https://github.com/nikhil8725/cmf-smart-dial.git
cd cmf-smart-dial

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode
open Dial.xcodeproj
```

---

## 📜 License & Credits

- Built with Swift 5.10+ & SwiftUI for macOS 14 Sonoma / Sequoia.
- Original concept inspired by [`athulrajt/dial`](https://github.com/athulrajt/dial).
- Distributed under the [MIT License](LICENSE).
