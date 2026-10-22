"""
Modular Shell Execution Action.
Runs local shell scripts, binaries, or terminal commands safely with timeouts.
"""

import os
import subprocess
from typing import Any, Dict
from actions.base import BaseAction, ActionResult


class ShellExecutorAction(BaseAction):
    """Executes a local command or shell script."""

    def __init__(self):
        super().__init__("shell")

    def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> ActionResult:
        command = params.get("command")
        script_path = params.get("script_path")
        args = params.get("args", [])
        cwd = params.get("cwd") or os.getcwd()
        env_vars = params.get("env", {})
        timeout = float(params.get("timeout_seconds", 15.0))

        # Merge custom env variables with existing process env
        process_env = os.environ.copy()
        for k, v in env_vars.items():
            process_env[str(k)] = str(v)

        # Inject trigger context into environment variables for the shell script
        if "trigger" in context:
            process_env["TRIGGER_KEY"] = str(context.get("trigger", {}).get("key", ""))
            process_env["TRIGGER_PRESS_COUNT"] = str(context.get("trigger", {}).get("press_count", "1"))
            process_env["TRIGGER_TIMESTAMP"] = str(context.get("timestamp", ""))

        if script_path:
            # Expand ~ or relative paths
            script_abs = os.path.abspath(os.path.expanduser(script_path))
            if not os.path.exists(script_abs):
                return ActionResult(
                    success=False,
                    output="",
                    error=f"Script not found at path: {script_abs}"
                )
            if not os.access(script_abs, os.X_OK):
                # If script is not executable, invoke via bash or sh
                cmd_to_run = ["/bin/bash", script_abs] + [str(a) for a in args]
                use_shell = False
            else:
                cmd_to_run = [script_abs] + [str(a) for a in args]
                use_shell = False
        elif command:
            cmd_to_run = command
            use_shell = True
        else:
            return ActionResult(
                success=False,
                output="",
                error="Neither 'command' nor 'script_path' was provided in action params"
            )

        try:
            completed = subprocess.run(
                cmd_to_run,
                cwd=cwd,
                env=process_env,
                shell=use_shell,
                capture_output=True,
                text=True,
                timeout=timeout,
            )

            stdout = completed.stdout.strip()
            stderr = completed.stderr.strip()
            combined_output = stdout if not stderr else f"{stdout}\n[STDERR]: {stderr}".strip()

            if completed.returncode == 0:
                return ActionResult(
                    success=True,
                    output=combined_output or "Command executed successfully (no output)",
                    metadata={"returncode": completed.returncode}
                )
            else:
                return ActionResult(
                    success=False,
                    output=combined_output,
                    error=f"Process exited with non-zero code {completed.returncode}",
                    metadata={"returncode": completed.returncode}
                )

        except subprocess.TimeoutExpired:
            return ActionResult(
                success=False,
                output="",
                error=f"Execution timed out after {timeout} seconds",
                metadata={"timed_out": True}
            )
        except Exception as exc:
            return ActionResult(
                success=False,
                output="",
                error=f"Failed to execute command: {exc}"
            )
