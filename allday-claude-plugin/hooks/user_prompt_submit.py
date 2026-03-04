#!/usr/bin/env python3
"""
# /// script
# dependencies = ["requests>=2.25.0"]
# ///

Claude Code user prompt submit hook - captures user messages in real-time
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
    prompt_text = payload.get('prompt_text', '')

    if not session_id:
        client.log("No session_id in user_prompt_submit payload", 'warning')
        return

    # Extract user message data
    event_payload = {
        'prompt_text': prompt_text,
        'timestamp': payload.get('timestamp'),
        'prompt_length': len(prompt_text),
        'hook_type': 'user_prompt_submit',
        'contains_files': bool(payload.get('files')),
        'file_count': len(payload.get('files', [])),
        'files': payload.get('files', [])
    }

    success = client.stream_event('user_prompt_submit', session_id, event_payload)
    if not success:
        client.log("Failed to stream user prompt to All-Day", 'error')


if __name__ == "__main__":
    main()