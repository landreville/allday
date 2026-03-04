"""
Example WebSocket client for All-Day Claude Code integration in Python

This demonstrates how to connect to the All-Day WebSocket server
to receive real-time updates from Claude Code sessions.
"""

import json
import asyncio
import websockets
from typing import Dict, Callable, Optional
import logging


class AllDayWebSocketClient:
    def __init__(self, api_key: str, base_url: str = "ws://localhost:3000"):
        self.api_key = api_key
        self.base_url = base_url
        self.connections: Dict[str, websockets.WebSocketServerProtocol] = {}
        self.logger = logging.getLogger(__name__)

    async def subscribe_to_transcript(self, transcript_id: str):
        """Subscribe to a specific Claude Code transcript"""
        if transcript_id in self.connections:
            self.logger.info(f"Already subscribed to transcript {transcript_id}")
            return self.connections[transcript_id]

        ws_url = f"{self.base_url}/cable?api_key={self.api_key}"

        try:
            ws = await websockets.connect(ws_url)
            self.connections[transcript_id] = ws

            # Subscribe to the transcript channel
            subscribe_message = {
                "command": "subscribe",
                "identifier": json.dumps({
                    "channel": "TranscriptChannel",
                    "transcript_id": transcript_id
                })
            }

            await ws.send(json.dumps(subscribe_message))
            self.logger.info(f"Connected to All-Day WebSocket for transcript {transcript_id}")

            # Start listening for messages
            asyncio.create_task(self._listen_to_messages(transcript_id, ws))

            return ws

        except Exception as e:
            self.logger.error(f"Failed to connect to transcript {transcript_id}: {e}")
            raise

    async def _listen_to_messages(self, transcript_id: str, ws):
        """Listen for incoming WebSocket messages"""
        try:
            async for message in ws:
                data = json.loads(message)
                await self.handle_message(transcript_id, data)
        except websockets.exceptions.ConnectionClosed:
            self.logger.info(f"Connection closed for transcript {transcript_id}")
            self.connections.pop(transcript_id, None)
        except Exception as e:
            self.logger.error(f"Error listening to messages for transcript {transcript_id}: {e}")

    async def handle_message(self, transcript_id: str, data: dict):
        """Handle incoming WebSocket messages"""
        if data.get("type") == "confirm_subscription":
            self.logger.info(f"✓ Subscribed to transcript {transcript_id}")
            return

        if "message" in data:
            message_data = data["message"]
            event = message_data.get("event")
            message = message_data.get("message")
            event_data = message_data.get("data")

            # Route to appropriate handler
            handlers = {
                "session_started": self.on_session_started,
                "user_message": self.on_user_message,
                "tool_planning": self.on_tool_planning,
                "tool_result": self.on_tool_result,
                "assistant_message": self.on_assistant_message,
                "session_ended": self.on_session_ended,
            }

            handler = handlers.get(event)
            if handler:
                await handler(transcript_id, message or event_data)
            else:
                self.logger.warning(f"Unknown event: {event}")

    # Event handlers - override these in your implementation
    async def on_session_started(self, transcript_id: str, data: dict):
        self.logger.info(f"🎬 Session started for transcript {transcript_id}: {data}")

    async def on_user_message(self, transcript_id: str, message: dict):
        self.logger.info(f"👤 User message in transcript {transcript_id}: {message.get('content')}")

    async def on_tool_planning(self, transcript_id: str, message: dict):
        tool_name = message.get("metadata", {}).get("tool_name", "unknown")
        self.logger.info(f"🤔 Claude planning in transcript {transcript_id}: {tool_name}")

    async def on_tool_result(self, transcript_id: str, message: dict):
        tool_name = message.get("metadata", {}).get("tool_name", "unknown")
        self.logger.info(f"🔧 Tool result in transcript {transcript_id}: {tool_name}")

    async def on_assistant_message(self, transcript_id: str, message: dict):
        content = message.get("content", "")
        thinking = message.get("thinking", "")
        self.logger.info(f"🤖 Assistant response in transcript {transcript_id}: {len(content)} chars")

    async def on_session_ended(self, transcript_id: str, data: dict):
        duration = data.get("duration", 0)
        message_count = data.get("message_count", 0)
        self.logger.info(f"🏁 Session ended for transcript {transcript_id}: {message_count} messages in {duration}s")

    async def unsubscribe_from_transcript(self, transcript_id: str):
        """Unsubscribe from a transcript"""
        ws = self.connections.get(transcript_id)
        if ws:
            await ws.close()
            self.connections.pop(transcript_id, None)
            self.logger.info(f"Unsubscribed from transcript {transcript_id}")

    async def disconnect(self):
        """Close all connections"""
        for transcript_id, ws in list(self.connections.items()):
            await ws.close()
        self.connections.clear()
        self.logger.info("Disconnected from all transcripts")


class CustomAllDayClient(AllDayWebSocketClient):
    """Example of custom client with specific behavior"""

    def __init__(self, api_key: str, base_url: str = "ws://localhost:3000"):
        super().__init__(api_key, base_url)
        self.session_data = {}

    async def on_session_started(self, transcript_id: str, data: dict):
        self.session_data[transcript_id] = {
            "start_time": data.get("metadata", {}).get("timestamp"),
            "messages": [],
            "tools_used": []
        }
        await super().on_session_started(transcript_id, data)

    async def on_user_message(self, transcript_id: str, message: dict):
        if transcript_id in self.session_data:
            self.session_data[transcript_id]["messages"].append({
                "role": "user",
                "content": message.get("content"),
                "timestamp": message.get("timestamp")
            })
        await super().on_user_message(transcript_id, message)

    async def on_tool_result(self, transcript_id: str, message: dict):
        if transcript_id in self.session_data:
            tool_name = message.get("metadata", {}).get("tool_name")
            if tool_name:
                self.session_data[transcript_id]["tools_used"].append(tool_name)
        await super().on_tool_result(transcript_id, message)

    async def on_assistant_message(self, transcript_id: str, message: dict):
        if transcript_id in self.session_data:
            self.session_data[transcript_id]["messages"].append({
                "role": "assistant",
                "content": message.get("content"),
                "thinking": message.get("thinking"),
                "timestamp": message.get("timestamp")
            })
        await super().on_assistant_message(transcript_id, message)

    def get_session_summary(self, transcript_id: str) -> dict:
        """Get summary of captured session data"""
        return self.session_data.get(transcript_id, {})


# Example usage
async def main():
    """Example usage of the WebSocket client"""
    logging.basicConfig(level=logging.INFO)

    # Initialize client
    client = CustomAllDayClient("your-api-key-here")

    # Subscribe to a transcript
    transcript_id = "transcript-123"
    await client.subscribe_to_transcript(transcript_id)

    # Keep the connection alive
    try:
        await asyncio.sleep(60)  # Listen for 1 minute
    except KeyboardInterrupt:
        print("\nShutting down...")

    # Clean up
    await client.disconnect()

    # Print session summary
    summary = client.get_session_summary(transcript_id)
    print(f"\nSession Summary: {json.dumps(summary, indent=2)}")


if __name__ == "__main__":
    asyncio.run(main())