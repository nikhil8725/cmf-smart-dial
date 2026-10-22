"""
Configuration Loader & Validator.
Parses JSON or YAML config files, validates trigger mappings, and provides defaults.
"""

import json
import logging
import os
import re
from typing import Any, Dict, List, Optional

logger = logging.getLogger("mac_trigger_service.config")

# Alias map for common key names to pynput canonical representations
KEY_ALIASES = {
    # Media keys
    "play": "media_play_pause",
    "play_pause": "media_play_pause",
    "playpause": "media_play_pause",
    "media_play": "media_play_pause",
    "media_play_pause": "media_play_pause",
    "next": "media_next",
    "next_track": "media_next",
    "media_next": "media_next",
    "prev": "media_previous",
    "previous": "media_previous",
    "previous_track": "media_previous",
    "media_previous": "media_previous",
    "media_prev": "media_previous",
    "volume_up": "media_volume_up",
    "media_volume_up": "media_volume_up",
    "volume_down": "media_volume_down",
    "media_volume_down": "media_volume_down",
    "mute": "media_volume_mute",
    "volume_mute": "media_volume_mute",
    "media_volume_mute": "media_volume_mute",
}

# Modifiers for hotkey parsing
MODIFIERS = {"ctrl", "control", "alt", "option", "cmd", "command", "shift", "super"}


def normalize_trigger_key(raw_key: str) -> str:
    """
    Normalizes human-friendly key names and combinations.
    Examples:
      'next track' -> '<media_next>'
      'play_pause' -> '<media_play_pause>'
      'ctrl+alt+k' -> '<ctrl>+<alt>+k'
      '<cmd>+<shift>+p' -> '<cmd>+<shift>+p'
    """
    s = raw_key.strip().lower().replace(" ", "_")

    # Check direct media key aliases
    if s in KEY_ALIASES:
        return f"<{KEY_ALIASES[s]}>"
    if s.startswith("<") and s.endswith(">"):
        inner = s[1:-1]
        if inner in KEY_ALIASES:
            return f"<{KEY_ALIASES[inner]}>"
        return s

    # Check if this is a combination like ctrl+cmd+k or <ctrl>+<cmd>+k
    parts = [p.strip() for p in s.split("+") if p.strip()]
    normalized_parts = []
    for p in parts:
        clean_p = p.strip("<>")
        # Canonical modifier names for pynput: ctrl, alt, cmd, shift
        if clean_p in ("control", "ctrl"):
            normalized_parts.append("<ctrl>")
        elif clean_p in ("alt", "option"):
            normalized_parts.append("<alt>")
        elif clean_p in ("cmd", "command", "super"):
            normalized_parts.append("<cmd>")
        elif clean_p == "shift":
            normalized_parts.append("<shift>")
        elif clean_p in KEY_ALIASES:
            normalized_parts.append(f"<{KEY_ALIASES[clean_p]}>")
        else:
            # Single character or named key
            normalized_parts.append(clean_p)

    return "+".join(normalized_parts)


class TriggerConfig:
    """Structured representation of a single mapped trigger."""

    def __init__(self, data: Dict[str, Any], index: int):
        self.raw_data = data
        self.id = data.get("id", f"trigger_{index}")
        self.name = data.get("name", self.id)
        self.enabled = bool(data.get("enabled", True))

        trigger_data = data.get("trigger", {})
        if not trigger_data.get("key"):
            raise ValueError(f"Trigger #{index} ('{self.name}') missing 'trigger.key'")

        self.raw_key = str(trigger_data["key"])
        self.normalized_key = normalize_trigger_key(self.raw_key)
        self.press_count = int(trigger_data.get("press_count", 1))
        if self.press_count < 1:
            raise ValueError(f"Trigger '{self.name}' press_count must be >= 1")

        action_data = data.get("action", {})
        if not action_data.get("type"):
            raise ValueError(f"Trigger '{self.name}' missing 'action.type'")
        self.action_type = str(action_data["type"]).lower()
        self.action_params = action_data.get("params", {})

        # Optional notification overrides
        self.notify_config = data.get("notify", {})

    def __repr__(self) -> str:
        return f"<TriggerConfig id='{self.id}' key='{self.normalized_key}' count={self.press_count} action='{self.action_type}'>"


class AppConfig:
    """Full application configuration."""

    def __init__(self, raw: Dict[str, Any]):
        self.raw = raw

        # Service settings
        svc = raw.get("service", {})
        self.multi_press_timeout_ms = int(svc.get("multi_press_timeout_ms", 380))
        self.max_workers = int(svc.get("max_workers", 4))

        # Logging settings
        log = raw.get("logging", {})
        self.log_file = log.get("file", "trigger.log")
        self.log_level = log.get("level", "INFO").upper()
        self.log_max_bytes = int(log.get("max_bytes", 5 * 1024 * 1024))  # 5MB
        self.log_backup_count = int(log.get("backup_count", 3))

        # Global Notification settings
        notif = raw.get("notifications", {})
        self.notifications_enabled = bool(notif.get("enabled", True))
        self.notification_title = notif.get("title", "macOS Trigger Service")
        self.notification_sound = notif.get("sound", "Tink")

        # Parse triggers
        self.triggers: List[TriggerConfig] = []
        raw_triggers = raw.get("triggers", [])
        if not isinstance(raw_triggers, list):
            raise ValueError("'triggers' must be a list in config")

        for idx, t_data in enumerate(raw_triggers):
            t_obj = TriggerConfig(t_data, idx + 1)
            if t_obj.enabled:
                self.triggers.append(t_obj)


def load_config(config_path: str = "config.json") -> AppConfig:
    """Loads configuration from JSON or YAML file."""
    expanded_path = os.path.abspath(os.path.expanduser(config_path))
    if not os.path.exists(expanded_path):
        raise FileNotFoundError(f"Configuration file not found: {expanded_path}")

    _, ext = os.path.splitext(expanded_path)
    ext = ext.lower()

    with open(expanded_path, "r", encoding="utf-8") as f:
        if ext in (".yaml", ".yml"):
            try:
                import yaml
                data = yaml.safe_load(f)
            except ImportError:
                raise ImportError("PyYAML is required to parse YAML configs. Run 'pip install pyyaml'.")
        else:
            data = json.load(f)

    if not isinstance(data, dict):
        raise ValueError("Root configuration structure must be a JSON object / dictionary")

    config = AppConfig(data)
    logger.info("Loaded configuration from %s (%d active triggers)", expanded_path, len(config.triggers))
    return config
