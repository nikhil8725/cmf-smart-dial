"""
macOS Native Notification Integration using osascript.
Provides non-blocking, visually appealing desktop notifications with system sounds.
"""

import logging
import subprocess
import threading
from typing import Optional

logger = logging.getLogger("mac_trigger_service.notifier")

# Standard macOS notification sounds available in /System/Library/Sounds
VALID_SOUNDS = {
    "basso", "blow", "bottle", "frog", "funk", "glass", "hero",
    "morse", "ping", "pop", "purr", "sosumi", "submarine", "tink"
}


def _escape_applescript_string(text: str) -> str:
    """Safely escapes strings for AppleScript interpolation."""
    if text is None:
        return ""
    # Escape backslashes first, then double quotes
    return str(text).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", "")


def send_notification(
    title: str = "macOS Trigger Service",
    message: str = "",
    subtitle: Optional[str] = None,
    sound: Optional[str] = "Tink",
    enabled: bool = True,
    async_mode: bool = True
) -> bool:
    """
    Triggers a native macOS notification via osascript.
    
    :param title: Main notification header
    :param message: Primary notification body text
    :param subtitle: Optional secondary header
    :param sound: Sound name (e.g. 'Tink', 'Pop', 'Glass', or None for silent)
    :param enabled: Quick toggle to bypass notifications
    :param async_mode: Whether to execute asynchronously in a background thread
    :return: True if dispatched, False if disabled or failed
    """
    if not enabled:
        return False

    escaped_title = _escape_applescript_string(title)
    escaped_msg = _escape_applescript_string(message)

    script_parts = [f'display notification "{escaped_msg}" with title "{escaped_title}"']

    if subtitle:
        escaped_sub = _escape_applescript_string(subtitle)
        script_parts.append(f'subtitle "{escaped_sub}"')

    if sound:
        clean_sound = sound.strip()
        if clean_sound.lower() in VALID_SOUNDS or clean_sound:
            script_parts.append(f'sound name "{clean_sound}"')

    full_script = " ".join(script_parts)

    def _execute():
        try:
            res = subprocess.run(
                ["osascript", "-e", full_script],
                capture_output=True,
                text=True,
                timeout=5
            )
            if res.returncode != 0:
                logger.debug("osascript notification warning: %s", res.stderr.strip())
        except Exception as exc:
            logger.debug("Failed sending notification via osascript: %s", exc)

    if async_mode:
        t = threading.Thread(target=_execute, daemon=True, name="NotificationWorker")
        t.start()
        return True
    else:
        _execute()
        return True
