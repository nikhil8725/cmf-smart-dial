"""
Base Action interface and execution result model for modular triggers.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
import logging
import time
from typing import Any, Dict, Optional

logger = logging.getLogger("mac_trigger_service.actions.base")


@dataclass
class ActionResult:
    """Standardized result returned by any action execution."""
    success: bool
    output: str = ""
    error: Optional[str] = None
    execution_time_ms: float = 0.0
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __str__(self) -> str:
        status = "SUCCESS" if self.success else f"FAILED: {self.error}"
        return f"[{status}] (took {self.execution_time_ms:.1f}ms): {self.output.strip()}"


class BaseAction(ABC):
    """Abstract Base Class for modular actions."""

    def __init__(self, action_type: str):
        self.action_type = action_type
        self.logger = logging.getLogger(f"mac_trigger_service.actions.{action_type}")

    def run(self, params: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> ActionResult:
        """
        Executes the action with safety wrappers, timing, and error isolation.
        Ensures uncaught exceptions never crash the service.
        """
        context = context or {}
        start_time = time.perf_counter()
        self.logger.info("Executing action '%s' with params: %s", self.action_type, params)

        try:
            result = self.execute(params, context)
            result.execution_time_ms = (time.perf_counter() - start_time) * 1000
            if result.success:
                self.logger.info("Action '%s' completed successfully in %.1fms", 
                                 self.action_type, result.execution_time_ms)
            else:
                self.logger.warning("Action '%s' reported failure in %.1fms: %s", 
                                    self.action_type, result.execution_time_ms, result.error)
            return result
        except Exception as exc:
            elapsed_ms = (time.perf_counter() - start_time) * 1000
            self.logger.exception("Action '%s' failed with unhandled exception: %s", self.action_type, exc)
            return ActionResult(
                success=False,
                output="",
                error=f"Unhandled exception in {self.action_type}: {exc}",
                execution_time_ms=elapsed_ms,
            )

    @abstractmethod
    def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> ActionResult:
        """
        Subclasses must implement the actual execution logic.
        """
        raise NotImplementedError
