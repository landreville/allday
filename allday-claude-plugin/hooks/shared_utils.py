"""
Shared utilities for All-Day Claude Code hooks
"""
import json
import sys
import requests
import os
from typing import Dict, Any, Optional
from datetime import datetime


class AllDayClient:
    def __init__(self, api_url: str = None, api_key: str = None, debug: bool = False):
        self.api_url = api_url or os.getenv('ALLDAY_API_URL', 'http://localhost:3000')
        self.api_key = api_key or os.getenv('ALLDAY_API_KEY')
        self.debug = debug or os.getenv('ALLDAY_DEBUG_MODE', '').lower() == 'true'
        self.session = requests.Session()

        if self.api_key:
            self.session.headers.update({
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            })

    def log(self, message: str, level: str = 'info'):
        """Log message if debug mode is enabled"""
        if self.debug:
            timestamp = datetime.now().isoformat()
            print(f"[{timestamp}] [{level.upper()}] AllDay: {message}", file=sys.stderr)

    def session_start(self, session_id: str, metadata: Dict[str, Any] = None) -> bool:
        """Notify All-Day of session start"""
        try:
            response = self.session.post(
                f"{self.api_url}/api/v1/claude_code/session_start",
                json={
                    "claude_code": {
                        "session_id": session_id,
                        "metadata": metadata or {}
                    }
                }
            )
            response.raise_for_status()
            self.log(f"Session start sent: {session_id}")
            return True
        except Exception as e:
            self.log(f"Failed to send session start: {e}", 'error')
            return False

    def session_end(self, session_id: str, metadata: Dict[str, Any] = None) -> bool:
        """Notify All-Day of session end"""
        try:
            response = self.session.post(
                f"{self.api_url}/api/v1/claude_code/session_end",
                json={
                    "claude_code": {
                        "session_id": session_id,
                        "metadata": metadata or {}
                    }
                }
            )
            response.raise_for_status()
            self.log(f"Session end sent: {session_id}")
            return True
        except Exception as e:
            self.log(f"Failed to send session end: {e}", 'error')
            return False

    def stream_event(self, event_type: str, session_id: str, payload: Dict[str, Any]) -> bool:
        """Stream an event to All-Day"""
        try:
            response = self.session.post(
                f"{self.api_url}/api/v1/claude_code/stream_event",
                json={
                    "claude_code": {
                        "event_type": event_type,
                        "session_id": session_id,
                        "timestamp": datetime.now().isoformat(),
                        "payload": payload
                    }
                }
            )
            response.raise_for_status()
            self.log(f"Event streamed: {event_type} for session {session_id}")
            return True
        except Exception as e:
            self.log(f"Failed to stream event {event_type}: {e}", 'error')
            return False


def read_hook_payload() -> Optional[Dict[str, Any]]:
    """Read and parse hook payload from stdin"""
    try:
        payload = json.loads(sys.stdin.read())
        return payload
    except json.JSONDecodeError as e:
        print(f"Failed to parse hook payload: {e}", file=sys.stderr)
        return None


def get_client() -> AllDayClient:
    """Get configured All-Day client"""
    return AllDayClient()


def should_stream() -> bool:
    """Check if streaming is enabled"""
    return os.getenv('ALLDAY_ENABLE_STREAMING', 'true').lower() == 'true'