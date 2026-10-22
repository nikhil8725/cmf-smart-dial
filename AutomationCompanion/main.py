#!/usr/bin/env python3
"""
macOS Global Input Trigger Service.
Production-grade background service listening for global media keys and hotkeys
to execute modular automation actions.
"""

import argparse
import logging
from logging.handlers import RotatingFileHandler
import os
import signal
import sys
import time

from actions import default_registry
from config_loader import load_config, AppConfig
from listener import GlobalTriggerListener, check_accessibility_permissions
from notifier import send_notification


def setup_logging(config: AppConfig) -> logging.Logger:
    """Configures dual-channel logging (RotatingFileHandler for trigger.log + StreamHandler)."""
    root_logger = logging.getLogger()
    root_logger.setLevel(getattr(logging, config.log_level, logging.INFO))

    # Clear existing handlers
    for h in list(root_logger.handlers):
        root_logger.removeHandler(h)

    # Format: Timestamp [LEVEL] [Thread] Module: Message
    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] [%(threadName)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # 1. Rotating File Handler (trigger.log)
    log_file_path = os.path.abspath(os.path.expanduser(config.log_file))
    os.makedirs(os.path.dirname(log_file_path) or ".", exist_ok=True)
    file_handler = RotatingFileHandler(
        log_file_path,
        maxBytes=config.log_max_bytes,
        backupCount=config.log_backup_count,
        encoding="utf-8"
    )
    file_handler.setFormatter(formatter)
    file_handler.setLevel(getattr(logging, config.log_level, logging.INFO))
    root_logger.addHandler(file_handler)

    # 2. Console Handler with clean format
    console_formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S"
    )
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(console_formatter)
    console_handler.setLevel(getattr(logging, config.log_level, logging.INFO))
    root_logger.addHandler(console_handler)

    logger = logging.getLogger("mac_trigger_service.main")
    logger.info("Logging initialized -> File: %s (Level: %s)", log_file_path, config.log_level)
    return logger


def parse_args():
    parser = argparse.ArgumentParser(
        description="macOS Background Service for Global Key & Media Triggers"
    )
    parser.add_argument(
        "-c", "--config",
        default="config.json",
        help="Path to configuration file (JSON or YAML). Default: config.json"
    )
    parser.add_argument(
        "--check-permissions",
        action="store_true",
        help="Verify macOS Accessibility permissions and exit."
    )
    parser.add_argument(
        "--prompt-permissions",
        action="store_true",
        help="Trigger macOS Accessibility authorization prompt."
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List configured triggers and supported action types, then exit."
    )
    parser.add_argument(
        "--test-trigger",
        metavar="TRIGGER_ID",
        help="Simulate execution of a configured trigger by its ID and exit."
    )
    return parser.parse_args()


def print_permissions_banner(is_trusted: bool):
    if is_trusted:
        print("\n✅ macOS Accessibility Permissions: GRANTED")
        print("   The global input listener has full access to monitor key taps.\n")
    else:
        print("\n❌ macOS Accessibility Permissions: NOT GRANTED")
        print("   macOS requires Accessibility permissions for global keyboard event taps.")
        print("   To grant permission:")
        print("   1. Open: System Settings > Privacy & Security > Accessibility")
        print("   2. Click the '+' button or toggle ON your Terminal / Python application.")
        print("   3. (Optional) Run with --prompt-permissions to open the macOS system prompt.\n")


def main():
    args = parse_args()

    # Handle Accessibility permission checks early
    if args.check_permissions or args.prompt_permissions:
        trusted = check_accessibility_permissions(prompt=args.prompt_permissions)
        print_permissions_banner(trusted)
        sys.exit(0 if trusted else 1)

    # Load configuration
    try:
        config = load_config(args.config)
    except Exception as exc:
        print(f"Error loading configuration from '{args.config}': {exc}", file=sys.stderr)
        sys.exit(1)

    # Setup dual logging (trigger.log + console)
    logger = setup_logging(config)

    # Handle --list
    if args.list:
        print("\n================== CONFIGURATION SUMMARY ==================")
        print(f"Config File: {os.path.abspath(args.config)}")
        print(f"Multi-press Timeout: {config.multi_press_timeout_ms} ms")
        print(f"Worker Concurrency: {config.max_workers} threads")
        print(f"Log Destination: {os.path.abspath(config.log_file)}")
        print("\n--- Registered Triggers ---")
        for t in config.triggers:
            status = "ENABLED" if t.enabled else "DISABLED"
            print(f" • [{t.id}] '{t.name}': Key='{t.normalized_key}' | Presses={t.press_count} | Action={t.action_type} ({status})")
        print("\n--- Available Action Handlers ---")
        for act in default_registry.registered_types:
            print(f" • {act}")
        print("===========================================================\n")
        sys.exit(0)

    # Handle --test-trigger
    if args.test_trigger:
        target_id = args.test_trigger.strip()
        matched = next((t for t in config.triggers if t.id == target_id), None)
        if not matched:
            print(f"Error: Trigger ID '{target_id}' not found in configuration.", file=sys.stderr)
            sys.exit(1)

        print(f"Testing execution of trigger '{matched.name}' (Action: {matched.action_type})...")
        context = {
            "trigger": {
                "id": matched.id,
                "name": matched.name,
                "key": matched.normalized_key,
                "press_count": matched.press_count,
            },
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
        res = default_registry.execute(matched.action_type, matched.action_params, context)
        print(f"Result: {res}")
        sys.exit(0 if res.success else 1)

    # Check accessibility permissions
    trusted = check_accessibility_permissions(prompt=False)
    if not trusted:
        logger.warning("Accessibility permission is not currently granted to this process.")
        print_permissions_banner(trusted)
        logger.info("Attempting to request permission prompt from macOS...")
        check_accessibility_permissions(prompt=True)

    # Initialize and start listener
    service = GlobalTriggerListener(config, default_registry)

    # Signal handlers for clean termination
    stop_event = threading.Event()

    def handle_signal(sig, frame):
        sig_name = signal.Signals(sig).name
        logger.info("Received termination signal (%s). Shutting down cleanly...", sig_name)
        stop_event.set()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    service.start()
    logger.info("macOS Trigger Service is running. Press Ctrl+C to stop.")

    # Send startup notification if enabled
    if config.notifications_enabled:
        send_notification(
            title=config.notification_title,
            message=f"Background service active ({len(config.triggers)} triggers registered)",
            sound="Pop"
        )

    # Service heartbeat loop
    try:
        while not stop_event.is_set():
            time.sleep(0.5)
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received.")
    finally:
        service.stop()
        logger.info("macOS Trigger Service cleanly exited.")


if __name__ == "__main__":
    main()
