/**
 * Example WebSocket client for All-Day Claude Code integration
 *
 * This demonstrates how to connect to the All-Day WebSocket server
 * to receive real-time updates from Claude Code sessions.
 */

class AllDayWebSocketClient {
  constructor(apiKey, baseUrl = 'ws://localhost:3000') {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
    this.connections = new Map(); // transcriptId -> WebSocket
  }

  /**
   * Subscribe to a specific Claude Code transcript
   */
  subscribeToTranscript(transcriptId) {
    if (this.connections.has(transcriptId)) {
      console.log(`Already subscribed to transcript ${transcriptId}`);
      return this.connections.get(transcriptId);
    }

    const wsUrl = `${this.baseUrl}/cable?api_key=${encodeURIComponent(this.apiKey)}`;
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      console.log(`Connected to All-Day WebSocket for transcript ${transcriptId}`);

      // Subscribe to the transcript channel
      const subscribeMessage = {
        command: 'subscribe',
        identifier: JSON.stringify({
          channel: 'TranscriptChannel',
          transcript_id: transcriptId
        })
      };

      ws.send(JSON.stringify(subscribeMessage));
    };

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.handleMessage(transcriptId, data);
    };

    ws.onclose = (event) => {
      console.log(`WebSocket closed for transcript ${transcriptId}:`, event.code, event.reason);
      this.connections.delete(transcriptId);
    };

    ws.onerror = (error) => {
      console.error(`WebSocket error for transcript ${transcriptId}:`, error);
    };

    this.connections.set(transcriptId, ws);
    return ws;
  }

  /**
   * Handle incoming WebSocket messages
   */
  handleMessage(transcriptId, data) {
    if (data.type === 'confirm_subscription') {
      console.log(`✓ Subscribed to transcript ${transcriptId}`);
      return;
    }

    if (data.message) {
      const { event, message, data: eventData } = data.message;

      switch (event) {
        case 'session_started':
          this.onSessionStarted(transcriptId, eventData);
          break;

        case 'user_message':
          this.onUserMessage(transcriptId, message);
          break;

        case 'tool_planning':
          this.onToolPlanning(transcriptId, message);
          break;

        case 'tool_result':
          this.onToolResult(transcriptId, message);
          break;

        case 'assistant_message':
          this.onAssistantMessage(transcriptId, message);
          break;

        case 'session_ended':
          this.onSessionEnded(transcriptId, eventData);
          break;

        default:
          console.log(`Unknown event: ${event}`, data.message);
      }
    }
  }

  /**
   * Event handlers - override these in your implementation
   */

  onSessionStarted(transcriptId, data) {
    console.log(`🎬 Session started for transcript ${transcriptId}:`, data);
  }

  onUserMessage(transcriptId, message) {
    console.log(`👤 User message in transcript ${transcriptId}:`, {
      content: message.content,
      timestamp: message.timestamp
    });
  }

  onToolPlanning(transcriptId, message) {
    console.log(`🤔 Claude planning in transcript ${transcriptId}:`, {
      thinking: message.thinking,
      toolName: message.metadata?.tool_name,
      timestamp: message.timestamp
    });
  }

  onToolResult(transcriptId, message) {
    console.log(`🔧 Tool result in transcript ${transcriptId}:`, {
      toolName: message.metadata?.tool_name,
      success: message.metadata?.hook_data?.success !== false,
      timestamp: message.timestamp
    });
  }

  onAssistantMessage(transcriptId, message) {
    console.log(`🤖 Assistant response in transcript ${transcriptId}:`, {
      content: message.content,
      thinking: message.thinking,
      timestamp: message.timestamp
    });
  }

  onSessionEnded(transcriptId, data) {
    console.log(`🏁 Session ended for transcript ${transcriptId}:`, data);
  }

  /**
   * Unsubscribe from a transcript
   */
  unsubscribeFromTranscript(transcriptId) {
    const ws = this.connections.get(transcriptId);
    if (ws) {
      ws.close();
      this.connections.delete(transcriptId);
      console.log(`Unsubscribed from transcript ${transcriptId}`);
    }
  }

  /**
   * Close all connections
   */
  disconnect() {
    this.connections.forEach((ws, transcriptId) => {
      ws.close();
    });
    this.connections.clear();
    console.log('Disconnected from all transcripts');
  }
}

// Example usage
if (typeof window !== 'undefined') {
  // Browser environment
  window.AllDayWebSocketClient = AllDayWebSocketClient;

  // Example initialization
  window.initAllDayClient = function(apiKey, transcriptId) {
    const client = new AllDayWebSocketClient(apiKey);
    client.subscribeToTranscript(transcriptId);
    return client;
  };

} else if (typeof module !== 'undefined') {
  // Node.js environment
  module.exports = AllDayWebSocketClient;
}

/*
Usage Examples:

// In browser:
const client = new AllDayWebSocketClient('your-api-key');
client.subscribeToTranscript('transcript-123');

// In Node.js:
const AllDayWebSocketClient = require('./websocket_client');
const client = new AllDayWebSocketClient('your-api-key', 'ws://localhost:3000');

// Custom event handling:
class MyAllDayClient extends AllDayWebSocketClient {
  onUserMessage(transcriptId, message) {
    // Custom handling for user messages
    this.updateUI('user', message.content);
  }

  onAssistantMessage(transcriptId, message) {
    // Custom handling for assistant messages
    this.updateUI('assistant', message.content, message.thinking);
  }
}
*/