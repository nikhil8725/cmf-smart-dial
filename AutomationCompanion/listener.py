"""
Global Event Listener & Trigger Engine.
Monitors system-wide keyboard events and media keys via macOS CGEventTap,
resolves multi-press sequences, and dispatches actions asynchronously to a worker pool.
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import logging
import threading
import time
from typing import Callable, Dict, List, Optional, Tuple

import pynput.keyboard
from pynput.keyboard import HotKey, Key, KeyCode, Listener

from actions import default_registry, ActionRegistry
from actions.base import ActionResult
from config_loader import AppConfig, TriggerConfig
from notifier import send_notification

logger = logging.getLogger("mac_trigger_service.listener")


def check_accessibility_permissions(prompt: bool = False) -> bool:
    """
    Checks if the process has macOS Accessibility permissions required for CGEventTap.
    
    :param prompt: If True and permissions are missing, triggers macOS system prompt.
    :return: True if granted, False otherwise.
    """
    try:
        import ApplicationServices
        if prompt:
            options = {ApplicationServices.kAXTrustedCheckOptionPrompt: True}
            return ApplicationServices.AXIsProcessTrustedWithOptions(options)
        return ApplicationServices.AXIsProcessTrusted()
    except Exception as exc:
        logger.warning("Could not query macOS ApplicationServices for accessibility: %s", exc)
        return True  # Fallback to attempting listener startup


class MultiPressDetector:
    """
    Detects single, double, or N-press sequences for keys with configurable timeouts.
    Dispatches immediately if the maximum expected press count is reached.
    """

    def __init__(self, timeout_ms: int = 380):
        self.timeout = timeout_ms / 1000.0
        self.timers: Dict[str, threading.Timer] = {}
        self.counts: Dict[str, int] = {}
        self.max_counts: Dict[str, int] = {}
        self.lock = threading.Lock()

    def set_max_count(self, key_id: str, max_count: int) -> None:
        """Register the maximum press count configured for a given key."""
        with self.lock:
            self.max_counts[key_id] = max(self.max_counts.get(key_id, 1), max_count)

    def record_press(self, key_id: str, dispatch_callback: Callable[[str, int], None]) -> None:
        """
        Records a key press. If only 1 press is expected, dispatches with 0ms latency.
        Otherwise manages debounce window for double/multi-tap detection.
        """
        with self.lock:
            max_expected = self.max_counts.get(key_id, 1)

            # Instant dispatch for keys with no multi-press triggers
            if max_expected <= 1:
                dispatch_callback(key_id, 1)
                return

            current_count = self.counts.get(key_id, 0) + 1
            self.counts[key_id] = current_count

            # Cancel any existing debounce timer for this key
            existing_timer = self.timers.pop(key_id, None)
            if existing_timer:
                existing_timer.cancel()

            # If we've reached the highest registered press count, fire immediately!
            if current_count >= max_expected:
                self.counts.pop(key_id, None)
                dispatch_callback(key_id, current_count)
                return

            # Otherwise, start debounce timer waiting for potential additional presses
            def _on_timeout():
                with self.lock:
                    final_count = self.counts.pop(key_id, 0)
                    self.timers.pop(key_id, None)
                if final_count > 0:
                    dispatch_callback(key_id, final_count)

            timer = threading.Timer(self.timeout, _on_timeout)
            timer.daemon = True
            self.timers[key_id] = timer
            timer.start()

    def reset(self) -> None:
        """Cancel all pending timers and clear state."""
        with self.lock:
            for timer in self.timers.values():
                timer.cancel()
            self.timers.clear()
            self.counts.clear()


class GlobalTriggerListener:
    """
    Production-grade background service listener managing macOS event tap,
    multi-press resolution, and thread-pooled action execution.
    """

    def __init__(self, config: AppConfig, registry: Optional[ActionRegistry] = None):
        self.config = config
        self.registry = registry or default_registry
        self.executor = ThreadPoolExecutor(
            max_workers=self.config.max_workers,
            thread_name_prefix="ActionWorker"
        )
        self.multi_press = MultiPressDetector(timeout_ms=self.config.multi_press_timeout_ms)
        self._listener: Optional[Listener] = None
        self._hotkeys: List[HotKey] = []
        self._running = False
        self._lock = threading.Lock()

        # Map: normalized_key -> { press_count: TriggerConfig }
        self._trigger_map: Dict[str, Dict[int, TriggerConfig]] = {}
        self._setup_triggers()

    def _setup_triggers(self) -> None:
        """Indexes active triggers and prepares HotKey matchers."""
        self._trigger_map.clear()

        for trigger in self.config.triggers:
            key_id = trigger.normalized_key
            if key_id not in self._trigger_map:
                self._trigger_map[key_id] = {}
            self._trigger_map[key_id][trigger.press_count] = trigger
            self.multi_press.set_max_count(key_id, trigger.press_count)
            logger.info("Registered trigger '%s': Key=%s, PressCount=%d, Action=%s",
                        trigger.name, key_id, trigger.press_count, trigger.action_type)

        # Build HotKey instances for each unique key combination
        self._hotkeys = []
        for key_id in self._trigger_map:
            try:
                parsed_keys = HotKey.parse(key_id)
                # Create activation callback bound to this specific key_id
                def make_activation_callback(target_key: str):
                    return lambda: self._on_hotkey_activated(target_key)

                hotkey = HotKey(parsed_keys, make_activation_callback(key_id))
                self._hotkeys.append(hotkey)
                logger.debug("Compiled HotKey matcher for '%s': %s", key_id, parsed_keys)
            except Exception as exc:
                logger.error("Failed to compile HotKey matcher for '%s': %s", key_id, exc)

    def _on_hotkey_activated(self, key_id: str) -> None:
        """Invoked when a hotkey combination is fully depressed."""
        logger.debug("Key activation detected for '%s'", key_id)
        self.multi_press.record_press(key_id, self._dispatch_matched_trigger)

    def _dispatch_matched_trigger(self, key_id: str, press_count: int) -> None:
        """Finds matching trigger and submits execution to worker pool."""
        triggers_for_key = self._trigger_map.get(key_id, {})
        trigger = triggers_for_key.get(press_count)

        if not trigger:
            logger.warning("No action registered for key '%s' with press_count=%d", key_id, press_count)
            return

        now_iso = datetime.now(timezone.utc).astimezone().isoformat()
        context = {
            "trigger": {
                "id": trigger.id,
                "name": trigger.name,
                "key": key_id,
                "press_count": press_count,
            },
            "timestamp": now_iso,
        }

        logger.info("Trigger fired: '%s' (%s, count=%d). Submitting to worker pool...",
                    trigger.name, key_id, press_count)
        self.executor.submit(self._execute_action_worker, trigger, context)

    def _execute_action_worker(self, trigger: TriggerConfig, context: dict) -> None:
        """Worker thread executing action, logging result, and sending notification."""
        t_name = trigger.name
        action_type = trigger.action_type
        params = trigger.action_params

        try:
            result: ActionResult = self.registry.execute(action_type, params, context)
            status_str = "SUCCESS" if result.success else f"FAILED: {result.error}"
            logger.info("Trigger '%s' finished execution: %s", t_name, status_str)

            # Determine notification settings
            notify_opts = trigger.notify_config
            notify_enabled = notify_opts.get("enabled", self.config.notifications_enabled)

            if notify_enabled:
                title = notify_opts.get("title") or self.config.notification_title
                sound = notify_opts.get("sound") or self.config.notification_sound
                
                # Format template message
                default_msg = f"{t_name}: {status_str}"
                template = notify_opts.get("message", default_msg)
                try:
                    formatted_msg = template.format(
                        name=t_name,
                        status="Success" if result.success else "Failed",
                        output=result.output.strip() or "No output",
                        error=result.error or "",
                        key=context["trigger"]["key"],
                        press_count=context["trigger"]["press_count"],
                        duration_ms=f"{result.execution_time_ms:.1f}",
                    )
                except Exception:
                    formatted_msg = f"{t_name}: {result.output.strip() if result.success else result.error}"

                send_notification(
                    title=title,
                    message=formatted_msg,
                    subtitle=f"{t_name} ({'✓' if result.success else '✗'})",
                    sound=sound if result.success else "Basso",
                    enabled=True,
                    async_mode=True
                )

        except Exception as exc:
            logger.exception("Critical error in worker executing trigger '%s': %s", t_name, exc)
            if self.config.notifications_enabled:
                send_notification(
                    title="Trigger Service Error",
                    message=f"Failed executing '{t_name}': {exc}",
                    sound="Basso",
                    enabled=True,
                    async_mode=True
                )

    def _on_key_press(self, key, injected: bool) -> None:
        """Internal callback on key press."""
        if injected:
            return
        if self._listener:
            try:
                canonical_key = self._listener.canonical(key)
                for hotkey in self._hotkeys:
                    hotkey.press(canonical_key)
            except Exception as exc:
                logger.debug("Error in key press evaluation: %s", exc)

    def _on_key_release(self, key, injected: bool) -> None:
        """Internal callback on key release."""
        if injected:
            return
        if self._listener:
            try:
                canonical_key = self._listener.canonical(key)
                for hotkey in self._hotkeys:
                    hotkey.release(canonical_key)
            except Exception as exc:
                logger.debug("Error in key release evaluation: %s", exc)

    def start(self) -> None:
        """Starts the background event listener."""
        with self._lock:
            if self._running:
                logger.warning("Listener already running")
                return

            logger.info("Initializing macOS keyboard event tap...")
            self._listener = Listener(
                on_press=self._on_key_press,
                on_release=self._on_key_release,
            )
            self._listener.daemon = True
            self._listener.start()
            self._running = True
            logger.info("Global event listener active and running.")

    def stop(self) -> None:
        """Stops the listener and worker pool cleanly."""
        with self._lock:
            if not self._running:
                return
            logger.info("Stopping global trigger service...")
            self._running = False
            self.multi_press.reset()
            if self._listener:
                self._listener.stop()
                self._listener = None
            self.executor.shutdown(wait=False)
            logger.info("Trigger service stopped.")

    @property
    def is_running(self) -> bool:
        return self._running and (self._listener is not None and self._listener.is_alive())
