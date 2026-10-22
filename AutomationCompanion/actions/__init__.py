"""
Action Registry and Dispatcher.
"""

from typing import Any, Dict, Optional, Type
from actions.base import BaseAction, ActionResult
from actions.shell_executor import ShellExecutorAction
from actions.api_trigger import ApiTriggerAction
from actions.service_toggle import ServiceToggleAction
from actions.system_logger import SystemLoggerAction


class ActionRegistry:
    """Central registry and factory for all trigger actions."""

    def __init__(self):
        self._actions: Dict[str, BaseAction] = {}
        # Register built-in standard actions
        self.register("shell", ShellExecutorAction())
        self.register("api", ApiTriggerAction())
        self.register("service", ServiceToggleAction())
        self.register("logger", SystemLoggerAction())

    def register(self, action_type: str, action_instance: BaseAction) -> None:
        """Register an instantiated action handler under an action_type."""
        self._actions[action_type.lower()] = action_instance

    def get(self, action_type: str) -> Optional[BaseAction]:
        """Fetch an action instance by type."""
        return self._actions.get(action_type.lower())

    def execute(self, action_type: str, params: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> ActionResult:
        """Finds and executes the requested action safely."""
        handler = self.get(action_type)
        if not handler:
            return ActionResult(
                success=False,
                error=f"Unknown action type '{action_type}'. Registered types: {list(self._actions.keys())}"
            )
        return handler.run(params, context)

    @property
    def registered_types(self) -> list:
        return sorted(list(self._actions.keys()))


# Global default registry singleton
default_registry = ActionRegistry()
