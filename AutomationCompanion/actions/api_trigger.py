"""
Modular API Webhook Action.
Triggers external HTTP/HTTPS webhooks or local service REST endpoints.
"""

from typing import Any, Dict, List
import requests
from actions.base import BaseAction, ActionResult


class ApiTriggerAction(BaseAction):
    """Sends an HTTP/HTTPS request to an external webhook or API."""

    def __init__(self):
        super().__init__("api")

    def execute(self, params: Dict[str, Any], context: Dict[str, Any]) -> ActionResult:
        url = params.get("url")
        if not url:
            return ActionResult(success=False, error="'url' parameter is required for api action")

        method = params.get("method", "POST").upper()
        headers = params.get("headers", {})
        query_params = params.get("params", {})
        timeout = float(params.get("timeout_seconds", 10.0))
        expected_status: List[int] = params.get("expected_status_codes", [200, 201, 202, 204])

        # Prepare payload: include configured json_data and optionally attach trigger context
        payload = params.get("json_data")
        if payload is None and method in ("POST", "PUT", "PATCH"):
            payload = {}

        if isinstance(payload, dict) and params.get("include_context", True):
            payload_to_send = payload.copy()
            payload_to_send.setdefault("_trigger_event", {
                "key": context.get("trigger", {}).get("key"),
                "press_count": context.get("trigger", {}).get("press_count"),
                "timestamp": context.get("timestamp"),
            })
        else:
            payload_to_send = payload

        try:
            response = requests.request(
                method=method,
                url=url,
                headers=headers,
                params=query_params,
                json=payload_to_send if isinstance(payload_to_send, (dict, list)) else None,
                data=payload_to_send if isinstance(payload_to_send, str) else None,
                timeout=timeout,
            )

            is_success = response.status_code in expected_status
            body_summary = response.text[:500] if response.text else "<empty response>"

            if is_success:
                return ActionResult(
                    success=True,
                    output=f"HTTP {response.status_code} {response.reason}: {body_summary}",
                    metadata={"status_code": response.status_code, "headers": dict(response.headers)}
                )
            else:
                return ActionResult(
                    success=False,
                    output=f"HTTP {response.status_code}: {body_summary}",
                    error=f"API returned status {response.status_code} (expected one of {expected_status})",
                    metadata={"status_code": response.status_code}
                )

        except requests.exceptions.Timeout:
            return ActionResult(
                success=False,
                error=f"API request to {url} timed out after {timeout}s",
                metadata={"timeout": True}
            )
        except requests.exceptions.ConnectionError as ce:
            return ActionResult(
                success=False,
                error=f"Connection error reaching {url}: {ce}",
                metadata={"connection_error": True}
            )
        except requests.exceptions.RequestException as re:
            return ActionResult(
                success=False,
                error=f"Request failed: {re}",
            )
