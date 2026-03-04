#!/usr/bin/env python3
"""
# /// script
# dependencies = ["requests>=2.25.0"]
# ///

Claude Code post-tool use hook - captures tool results and outcomes
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
    tool_name = payload.get('tool_name', '')
    tool_input = payload.get('tool_input', {})
    tool_output = payload.get('tool_output', '')

    if not session_id:
        client.log("No session_id in post_tool_use payload", 'warning')
        return

    # Extract tool result data
    event_payload = {
        'tool_name': tool_name,
        'tool_input': tool_input,
        'tool_output': tool_output,
        'timestamp': payload.get('timestamp'),
        'success': payload.get('success', True),
        'error': payload.get('error'),
        'hook_type': 'post_tool_use',
        'output_size': len(str(tool_output)),
        'execution_time': payload.get('execution_time'),
        'tool_category': get_tool_category(tool_name)
    }

    success = client.stream_event('post_tool_use', session_id, event_payload)
    if not success:
        client.log(f"Failed to stream post_tool_use for {tool_name} to All-Day", 'error')


def get_tool_category(tool_name: str) -> str:
    """Categorize the tool for better organization"""
    tool_categories = {
        'read': 'file_operations',
        'write': 'file_operations',
        'edit': 'file_operations',
        'multiedit': 'file_operations',
        'bash': 'system_operations',
        'grep': 'search',
        'glob': 'search',
        'task': 'agent_operations',
        'webfetch': 'web_operations',
        'websearch': 'web_operations'
    }
    return tool_categories.get(tool_name.lower(), 'other')


if __name__ == "__main__":
    main()