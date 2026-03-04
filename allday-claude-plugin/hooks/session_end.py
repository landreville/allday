#!/usr/bin/env python3
"""
# /// script
# dependencies = ["requests>=2.25.0"]
# ///

Claude Code session end hook - notifies All-Day when a session completes
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
        client.log("No session_id in session_end payload", 'warning')
        return

    # Extract metadata from the session end
    metadata = {
        'hook_type': 'session_end',
        'timestamp': payload.get('timestamp'),
        'duration': payload.get('duration'),
        'total_messages': payload.get('total_messages'),
        'total_tools_used': payload.get('total_tools_used'),
        'files_modified': payload.get('files_modified'),
        'completion_reason': payload.get('completion_reason', 'user_ended')
    }

    success = client.session_end(session_id, metadata)
    if not success:
        client.log("Failed to notify All-Day of session end", 'error')


if __name__ == "__main__":
    main()