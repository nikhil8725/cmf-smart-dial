"""
Modular Service & System Toggle Action for macOS.
Supports toggling system appearance (Dark Mode), audio mute, applications,
or local background services (e.g., Homebrew services, Docker containers).
"""

import subprocess
from typing import Any, Dict
from actions.base import BaseAction, ActionResult


class ServiceToggleAction(BaseAction):
    """Toggles macOS system settings, applications, or background daemons."""

    def __init__(self):
        super().__init__("service")

    def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> ActionResult:
        operation = params.get("operation", "").lower()

        if operation == "toggle_dark_mode":
            script = (
                'tell application "System Events"\n'
                '    tell appearance preferences\n'
                '        set dark mode to not dark mode\n'
                '        return dark mode\n'
                '    end tell\n'
                'end tell'
            )
            res = self._run_osascript(script)
            if res.success:
                mode = "Dark" if "true" in res.output.lower() else "Light"
                res.output = f"Appearance switched to {mode} Mode"
            return res

        elif operation == "toggle_mute":
            script = (
                'set isMuted to output muted of (get volume settings)\n'
                'set volume output muted (not isMuted)\n'
                'return not isMuted'
            )
            res = self._run_osascript(script)
            if res.success:
                status = "Muted" if "true" in res.output.lower() else "Unmuted"
                res.output = f"Audio output {status}"
            return res

        elif operation == "toggle_app":
            app_name = params.get("app_name")
            if not app_name:
                return ActionResult(success=False, error="'app_name' required for toggle_app")
            script = f'''
            tell application "System Events"
                set isRunning to (name of processes) contains "{app_name}"
            end tell
            if isRunning then
                tell application "{app_name}" to quit
                return "Quit {app_name}"
            else
                tell application "{app_name}" to activate
                return "Launched {app_name}"
            end if
            '''
            return self._run_osascript(script)

        elif operation == "brew_service":
            service_name = params.get("service_name")
            action = params.get("action", "restart")  # start, stop, restart
            if not service_name:
                return ActionResult(success=False, error="'service_name' required for brew_service")
            cmd = ["brew", "services", action, service_name]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                if proc.returncode == 0:
                    return ActionResult(success=True, output=proc.stdout.strip() or f"Brew service {service_name} {action}ed")
                else:
                    return ActionResult(success=False, error=proc.stderr.strip() or f"Failed to {action} {service_name}")
            except Exception as e:
                return ActionResult(success=False, error=str(e))

        elif operation == "applescript":
            script = params.get("script")
            if not script:
                return ActionResult(success=False, error="'script' parameter required for applescript operation")
            return self._run_osascript(script)

        else:
            return ActionResult(
                success=False,
                error=f"Unknown operation '{operation}'. Supported: toggle_dark_mode, toggle_mute, toggle_app, brew_service, applescript"
            )

    def _run_osascript(self, script: str) -> ActionResult:
        try:
            proc = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                text=True,
                timeout=8,
            )
            if proc.returncode == 0:
                return ActionResult(success=True, output=proc.stdout.strip())
            else:
                return ActionResult(success=False, error=proc.stderr.strip() or "AppleScript failed")
        except Exception as e:
            return ActionResult(success=False, error=f"Failed to run osascript: {e}")
