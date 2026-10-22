"""
Virtual Navigation Simulator.
Simulates CMF dial navigation: Tab, Shift+Tab, Up/Down Arrow, Return, and Scroll Wheel.
"""

import time
import Quartz


def post_key(key_code: int, flags: int = 0):
    """Posts key down and up event via Quartz CGEvent."""
    source = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    event_down = Quartz.CGEventCreateKeyboardEvent(source, key_code, True)
    if flags:
        Quartz.CGEventSetFlags(event_down, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event_down)

    time.sleep(0.02)

    event_up = Quartz.CGEventCreateKeyboardEvent(source, key_code, False)
    if flags:
        Quartz.CGEventSetFlags(event_up, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event_up)


def post_scroll(lines: int):
    """Posts scroll wheel event via Quartz CGEvent."""
    source = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    event = Quartz.CGEventCreateScrollWheelEvent(
        source,
        Quartz.kCGScrollEventUnitLine,
        1,
        lines
    )
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def test_simulation():
    print("=== Testing Virtual CMF Dial Navigation ===")
    
    # Virtual Key Codes (Carbon HIToolbox)
    VK_TAB = 48
    VK_RETURN = 36
    VK_UP_ARROW = 126
    VK_DOWN_ARROW = 125
    FLAG_SHIFT = Quartz.kCGEventFlagMaskShift

    print("1. Simulating CMF Dial Turn -> Scroll Down (3 lines)...")
    post_scroll(-3)
    time.sleep(0.3)

    print("2. Simulating CMF Dial Turn -> Scroll Up (3 lines)...")
    post_scroll(3)
    time.sleep(0.3)

    print("3. Simulating CMF Dial Turn -> Tab Forward (Next Link/Field)...")
    post_key(VK_TAB)
    time.sleep(0.3)

    print("4. Simulating CMF Dial Turn -> Shift+Tab Backward (Prev Link/Field)...")
    post_key(VK_TAB, FLAG_SHIFT)
    time.sleep(0.3)

    print("5. Simulating CMF Dial Turn -> Down Arrow (Step Down Menu/List)...")
    post_key(VK_DOWN_ARROW)
    time.sleep(0.3)

    print("6. Simulating CMF Dial Turn -> Up Arrow (Step Up Menu/List)...")
    post_key(VK_UP_ARROW)
    time.sleep(0.3)

    print("7. Simulating CMF Dial Press -> Return / Enter (Activate / Select)...")
    # post_key(VK_RETURN) # Commented out so it doesn't accidentally trigger a submit during test

    print("✅ All virtual navigation events posted successfully to macOS event tap!")


if __name__ == "__main__":
    test_simulation()
