#!/usr/bin/env python3
"""
# /// script
# dependencies = ["requests>=2.25.0"]
# ///

Claude Code session start hook - notifies All-Day when a new session begins
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from shared_utils import read_hook_payload, get_client, should_stream


def main():
    if not should_stream():
        return

    payload = read_hook_payload()
    if not payload:
        return

    client = get_client()
    session_id = payload.get('session_id')

    if not session_id:
        client.log("No session_id in session_start payload", 'warning')
        return

    # Extract metadata from the session start
    metadata = {
        'hook_type': 'session_start',
        'timestamp': payload.get('timestamp'),
        'project_path': payload.get('project_path'),
        'claude_model': payload.get('model'),
        'workspace': payload.get('workspace')
    }

    success = client.session_start(session_id, metadata)
    if not success:
        client.log("Failed to notify All-Day of session start", 'error')


if __name__ == "__main__":
    main()