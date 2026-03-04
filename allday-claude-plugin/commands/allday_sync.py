#!/usr/bin/env python3
"""
# /// script
# dependencies = ["requests>=2.25.0"]
# ///

All-Day sync command - manual session synchronization and status check
"""

import sys
import os
import json
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'hooks'))

from shared_utils import get_client
import argparse


def main():
    parser = argparse.ArgumentParser(description="Sync with All-Day app")
    parser.add_argument('action', choices=['status', 'test', 'sync'],
                       help='Action to perform')
    parser.add_argument('--session-id', help='Session ID for sync operations')

    args = parser.parse_args()
    client = get_client()

    if args.action == 'status':
        check_status(client)
    elif args.action == 'test':
        test_connection(client)
    elif args.action == 'sync':
        if not args.session_id:
            print("Error: --session-id required for sync action")
            sys.exit(1)
        sync_session(client, args.session_id)


def check_status(client):
    """Check connection status with All-Day"""
    try:
        response = client.session.get(f"{client.api_url}/up")
        if response.status_code == 200:
            print(f"✓ All-Day API is reachable at {client.api_url}")
            print(f"✓ API key configured: {'Yes' if client.api_key else 'No'}")
            print(f"✓ Debug mode: {'Yes' if client.debug else 'No'}")
        else:
            print(f"✗ All-Day API returned status {response.status_code}")
    except Exception as e:
        print(f"✗ Failed to connect to All-Day: {e}")


def test_connection(client):
    """Test the API connection with a dummy session"""
    test_session_id = "test-session-123"

    print("Testing All-Day API connection...")

    # Test session start
    if client.session_start(test_session_id, {"test": True}):
        print("✓ Session start API works")
    else:
        print("✗ Session start API failed")
        return

    # Test event streaming
    if client.stream_event('user_prompt_submit', test_session_id, {
        'prompt_text': 'Test message',
        'test': True
    }):
        print("✓ Event streaming API works")
    else:
        print("✗ Event streaming API failed")
        return

    # Test session end
    if client.session_end(test_session_id, {"test": True}):
        print("✓ Session end API works")
    else:
        print("✗ Session end API failed")
        return

    print("🎉 All API endpoints working correctly!")


def sync_session(client, session_id):
    """Manually sync a session with All-Day"""
    print(f"Syncing session {session_id} with All-Day...")

    # This would typically read from Claude Code's session files
    # and replay the conversation to All-Day
    print("Note: Manual session sync not yet implemented")
    print("Sessions are automatically synced via hooks when streaming is enabled")


if __name__ == "__main__":
    main()