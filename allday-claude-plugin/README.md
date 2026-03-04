# All-Day Claude Code Plugin

Stream Claude Code sessions to All-Day app in real-time for enhanced session tracking and analysis.

## Features

- **Real-time streaming**: Captures user messages, Claude responses, and tool usage as they happen
- **Session management**: Tracks session start/end with metadata
- **Tool monitoring**: Records Claude's thinking process and tool decisions
- **WebSocket broadcasting**: Live updates to connected All-Day clients
- **Configurable**: Easy setup with environment variables

## Installation

1. Copy this plugin directory to your Claude Code plugins folder
2. Configure your All-Day API credentials
3. Enable the plugin in Claude Code

## Configuration

Set these environment variables or configure in Claude Code settings:

```bash
export ALLDAY_API_URL="http://localhost:3000"
export ALLDAY_API_KEY="your-api-key-here"
export ALLDAY_ENABLE_STREAMING="true"
export ALLDAY_DEBUG_MODE="false"
```

## Usage

### Automatic Streaming (Recommended)

Once installed and configured, the plugin automatically streams:

- **Session events**: Start/end notifications with metadata
- **User messages**: Real-time capture of user prompts
- **Tool planning**: Claude's reasoning before tool use
- **Tool results**: Outcomes and responses from tool execution
- **Assistant responses**: Final responses and thinking

### Manual Commands

```bash
# Check connection status
/allday status

# Test API connectivity
/allday test

# Manual session sync (future feature)
/allday sync --session-id=abc123
```

## Hook Events

The plugin captures these Claude Code events:

1. **session_start**: New session initialization
2. **user_prompt_submit**: User input capture
3. **pre_tool_use**: Tool planning and reasoning
4. **post_tool_use**: Tool execution results
5. **stop**: Assistant response completion
6. **session_end**: Session termination

## Data Flow

```
Claude Code Session → Hooks → All-Day API → WebSocket → Clients
                         ↓
                  Real-time streaming
                         ↓
                  Database storage
                         ↓
                  Live dashboard updates
```

## API Integration

The plugin integrates with these All-Day endpoints:

- `POST /api/v1/claude_code/session_start`
- `POST /api/v1/claude_code/session_end`
- `POST /api/v1/claude_code/stream_event`
- `WebSocket /cable` (for real-time updates)

## Troubleshooting

### Debug Mode

Enable debug logging:
```bash
export ALLDAY_DEBUG_MODE="true"
```

### Connection Issues

Test the connection:
```bash
/allday status
/allday test
```

### Hook Not Firing

Ensure hooks have executable permissions:
```bash
chmod +x hooks/*.py
```

## Security

- API keys are transmitted via Authorization headers
- WebSocket connections require API key authentication
- All data is sent over HTTPS in production
- No sensitive data is logged in debug mode