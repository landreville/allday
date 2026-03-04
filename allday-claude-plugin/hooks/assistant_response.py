#!/usr/bin/env python3
"""
# /// script
# dependencies = ["requests>=2.25.0"]
# ///

Claude Code stop hook - captures Claude's final responses and thinking
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
    response_text = payload.get('response_text', '')
    thinking = payload.get('thinking', '')

    if not session_id:
        client.log("No session_id in stop hook payload", 'warning')
        return

    # Extract assistant response data
    event_payload = {
        'response_text': response_text,
        'thinking': thinking,
        'timestamp': payload.get('timestamp'),
        'hook_type': 'assistant_response',
        'response_length': len(response_text),
        'thinking_length': len(thinking),
        'stop_reason': payload.get('stop_reason', 'completed'),
        'token_usage': payload.get('token_usage', {}),
        'tools_used_count': payload.get('tools_used_count', 0),
        'files_modified': payload.get('files_modified', [])
    }

    success = client.stream_event('assistant_response', session_id, event_payload)
    if not success:
        client.log("Failed to stream assistant response to All-Day", 'error')


if __name__ == "__main__":
    main()