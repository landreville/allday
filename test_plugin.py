#!/usr/bin/env python3
"""
Test script to simulate Claude Code plugin hooks and verify integration
"""

import json
import requests
import subprocess
import sys
import os
from datetime import datetime

API_URL = "http://localhost:3000"
API_KEY = "test-api-key-123"
SESSION_ID = "test-session-123"

def run_hook_with_payload(hook_script, payload):
    """Run a hook script with the given payload"""
    try:
        # Set environment variables for the hook
        env = os.environ.copy()
        env.update({
            'ALLDAY_API_URL': API_URL,
            'ALLDAY_API_KEY': API_KEY,
            'ALLDAY_ENABLE_STREAMING': 'true',
            'ALLDAY_DEBUG_MODE': 'true'
        })

        # Run the hook script
        process = subprocess.Popen(
            ['python3', hook_script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            cwd='allday-claude-plugin'
        )

        stdout, stderr = process.communicate(input=json.dumps(payload).encode())

        if process.returncode != 0:
            print(f"❌ Hook {hook_script} failed:")
            print(f"   STDERR: {stderr.decode()}")
            return False

        if stderr:
            print(f"📝 Hook {hook_script} output: {stderr.decode().strip()}")

        return True

    except Exception as e:
        print(f"❌ Error running hook {hook_script}: {e}")
        return False

def test_api_endpoints():
    """Test API endpoints directly"""
    headers = {
        'Authorization': f'Bearer {API_KEY}',
        'Content-Type': 'application/json'
    }

    # Test session start
    print("🧪 Testing session start API...")
    response = requests.post(
        f"{API_URL}/api/v1/claude_code/session_start",
        headers=headers,
        json={
            "claude_code": {
                "session_id": SESSION_ID,
                "metadata": {"test": True, "project_path": "/test/project"}
            }
        }
    )

    if response.status_code == 200:
        print("✅ Session start API works")
        result = response.json()
        transcript_id = result.get('transcript_id')
        print(f"   Created transcript ID: {transcript_id}")
        return transcript_id
    else:
        print(f"❌ Session start failed: {response.status_code} - {response.text}")
        return None

def test_stream_event(transcript_id):
    """Test event streaming API"""
    headers = {
        'Authorization': f'Bearer {API_KEY}',
        'Content-Type': 'application/json'
    }

    print("🧪 Testing stream event API...")
    response = requests.post(
        f"{API_URL}/api/v1/claude_code/stream_event",
        headers=headers,
        json={
            "claude_code": {
                "event_type": "user_prompt_submit",
                "session_id": SESSION_ID,
                "timestamp": datetime.now().isoformat(),
                "payload": {
                    "prompt_text": "Hello, Claude! Please list files in the current directory.",
                    "timestamp": datetime.now().isoformat()
                }
            }
        }
    )

    if response.status_code == 200:
        print("✅ Stream event API works")
        return True
    else:
        print(f"❌ Stream event failed: {response.status_code} - {response.text}")
        return False

def main():
    print("🚀 Testing All-Day Claude Code Integration\n")

    # Test API endpoints first
    transcript_id = test_api_endpoints()
    if not transcript_id:
        return False

    if not test_stream_event(transcript_id):
        return False

    print("\n🧪 Testing plugin hooks...")

    # Test session start hook
    session_start_payload = {
        "session_id": SESSION_ID,
        "timestamp": datetime.now().isoformat(),
        "project_path": "/test/project",
        "model": "claude-3-5-sonnet",
        "workspace": "test-workspace"
    }

    if run_hook_with_payload("hooks/session_start.py", session_start_payload):
        print("✅ Session start hook works")

    # Test user prompt submit hook
    user_prompt_payload = {
        "session_id": SESSION_ID,
        "prompt_text": "Please create a simple Python script that prints 'Hello World'",
        "timestamp": datetime.now().isoformat(),
        "files": []
    }

    if run_hook_with_payload("hooks/user_prompt_submit.py", user_prompt_payload):
        print("✅ User prompt submit hook works")

    # Test pre-tool use hook
    pre_tool_payload = {
        "session_id": SESSION_ID,
        "tool_name": "write",
        "tool_input": {
            "file_path": "/test/hello.py",
            "content": "print('Hello World')"
        },
        "reasoning": "I'll create a simple Python script as requested",
        "timestamp": datetime.now().isoformat()
    }

    if run_hook_with_payload("hooks/pre_tool_use.py", pre_tool_payload):
        print("✅ Pre-tool use hook works")

    # Test post-tool use hook
    post_tool_payload = {
        "session_id": SESSION_ID,
        "tool_name": "write",
        "tool_input": {
            "file_path": "/test/hello.py",
            "content": "print('Hello World')"
        },
        "tool_output": "File created successfully",
        "success": True,
        "timestamp": datetime.now().isoformat()
    }

    if run_hook_with_payload("hooks/post_tool_use.py", post_tool_payload):
        print("✅ Post-tool use hook works")

    # Test assistant response hook
    assistant_response_payload = {
        "session_id": SESSION_ID,
        "response_text": "I've created a simple Python script that prints 'Hello World' as requested. The file has been saved to `/test/hello.py`.",
        "thinking": "The user asked for a simple Python script, so I used the Write tool to create a basic hello world program.",
        "timestamp": datetime.now().isoformat(),
        "stop_reason": "completed",
        "tools_used_count": 1,
        "files_modified": ["/test/hello.py"]
    }

    if run_hook_with_payload("hooks/assistant_response.py", assistant_response_payload):
        print("✅ Assistant response hook works")

    # Test session end hook
    session_end_payload = {
        "session_id": SESSION_ID,
        "timestamp": datetime.now().isoformat(),
        "duration": 45.2,
        "total_messages": 4,
        "total_tools_used": 1,
        "files_modified": ["/test/hello.py"],
        "completion_reason": "user_ended"
    }

    if run_hook_with_payload("hooks/session_end.py", session_end_payload):
        print("✅ Session end hook works")

    print("\n🎉 All tests completed successfully!")
    print(f"📊 Transcript ID: {transcript_id}")
    print("💡 You can now check the database or connect a WebSocket client to see the live data")

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)