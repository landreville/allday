#!/usr/bin/env python3
"""
Test WebSocket connectivity to All-Day
"""

import asyncio
import websockets
import json
import requests


async def test_websocket_connection():
    api_key = "test-api-key-123"
    transcript_id = 1

    # First, send a test message via API to trigger WebSocket broadcast
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }

    print("📡 Testing WebSocket connection...")

    try:
        # Connect to WebSocket
        ws_url = f"ws://localhost:3000/cable?api_key={api_key}"

        async with websockets.connect(ws_url) as websocket:
            print("✅ WebSocket connected successfully!")

            # Subscribe to transcript channel
            subscribe_message = {
                "command": "subscribe",
                "identifier": json.dumps({
                    "channel": "TranscriptChannel",
                    "transcript_id": transcript_id
                })
            }

            await websocket.send(json.dumps(subscribe_message))
            print("📺 Sent subscription message")

            # Wait for subscription confirmation
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                data = json.loads(response)

                if data.get("type") == "confirm_subscription":
                    print("✅ Subscription confirmed!")
                else:
                    print(f"📨 Received: {data}")

            except asyncio.TimeoutError:
                print("⏰ Timeout waiting for subscription confirmation")
                return False

            # Now trigger a test event via HTTP API
            print("🚀 Sending test event via API...")

            async def send_test_event():
                await asyncio.sleep(1)  # Give WebSocket time to settle

                response = requests.post(
                    "http://localhost:3000/api/v1/claude_code/stream_event",
                    headers=headers,
                    json={
                        "claude_code": {
                            "event_type": "user_prompt_submit",
                            "session_id": "test-session-123",
                            "timestamp": "2026-03-04T11:45:40.000Z",
                            "payload": {
                                "prompt_text": "WebSocket test message",
                                "timestamp": "2026-03-04T11:45:40.000Z"
                            }
                        }
                    }
                )
                print(f"📤 API response: {response.status_code}")

            # Send the test event in the background
            asyncio.create_task(send_test_event())

            # Listen for WebSocket messages
            try:
                for i in range(3):  # Listen for a few messages
                    response = await asyncio.wait_for(websocket.recv(), timeout=10.0)
                    data = json.loads(response)

                    print(f"📨 WebSocket message {i+1}: {json.dumps(data, indent=2)}")

                    if data.get("message", {}).get("event") == "user_message":
                        print("✅ Received real-time user message event!")
                        return True

            except asyncio.TimeoutError:
                print("⏰ Timeout waiting for WebSocket messages")
                return False

    except Exception as e:
        print(f"❌ WebSocket connection failed: {e}")
        return False

    return True


def main():
    print("🔌 Testing WebSocket Integration\n")

    success = asyncio.run(test_websocket_connection())

    if success:
        print("\n🎉 WebSocket integration test passed!")
    else:
        print("\n❌ WebSocket integration test failed!")

    return success


if __name__ == "__main__":
    import sys
    success = main()
    sys.exit(0 if success else 1)