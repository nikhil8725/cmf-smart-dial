"""
Modular System & Event Logging Action.
Appends structured event entries or system telemetry to a dedicated log file.
"""

from datetime import datetime, timezone
import json
import os
import subprocess
from typing import Any, Dict
from actions.base import BaseAction, ActionResult


class SystemLoggerAction(BaseAction):
    """Logs trigger executions and system telemetry to a designated log file."""

    def __init__(self):
        super().__init__("logger")

    def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> ActionResult:
        target_file = params.get("target_file", "events.log")
        log_format = params.get("format", "json").lower()
        custom_message = params.get("message", "")
        include_frontmost_app = params.get("include_frontmost_app", True)

        target_path = os.path.abspath(os.path.expanduser(target_file))
        os.makedirs(os.path.dirname(target_path) or ".", exist_ok=True)

        frontmost_app = self._get_frontmost_app() if include_frontmost_app else None
        now_iso = datetime.now(timezone.utc).astimezone().isoformat()

        entry = {
            "timestamp": now_iso,
            "message": custom_message,
            "trigger": context.get("trigger", {}),
            "frontmost_app": frontmost_app,
        }

        try:
            with open(target_path, "a", encoding="utf-8") as f:
                if log_format == "json":
                    f.write(json.dumps(entry) + "\n")
                else:
                    trigger_desc = f"{context.get('trigger', {}).get('key')} (presses: {context.get('trigger', {}).get('press_count')})"
                    line = f"[{now_iso}] Trigger: {trigger_desc} | ActiveApp: {frontmost_app or 'N/A'} | {custom_message}\n"
                    f.write(line)

            return ActionResult(
                success=True,
                output=f"Logged entry to {target_path}",
                metadata={"file": target_path, "entry": entry}
            )
        except Exception as exc:
            return ActionResult(
                success=False,
                error=f"Failed writing to log file {target_path}: {exc}"
            )

    def _get_frontmost_app(self) -> str:
        """Retrieves currently focused macOS application name."""
        try:
            script = 'tell application "System Events" to get name of first application process whose frontmost is true'
            proc = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                text=True,
                timeout=2,
            )
            return proc.stdout.strip() if proc.returncode == 0 else "Unknown"
        except Exception:
            return "Unknown"
