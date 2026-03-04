# frozen_string_literal: true

class Api::V1::ClaudeCodeController < Api::V1::BaseController
  before_action :find_or_create_agent, only: [:stream_event, :session_start, :session_end]
  before_action :find_or_create_transcript, only: [:stream_event, :session_start, :session_end]

  # POST /api/v1/claude_code/session_start
  def session_start
    @transcript.update!(
      status: :active,
      started_at: Time.current,
      metadata: session_start_params[:metadata] || {}
    )

    broadcast_session_event("session_started", {
      transcript_id: @transcript.id,
      session_id: @transcript.source_session_id,
      metadata: @transcript.metadata
    })

    render json: {
      success: true,
      transcript_id: @transcript.id,
      session_id: @transcript.source_session_id
    }
  end

  # POST /api/v1/claude_code/session_end
  def session_end
    @transcript.update!(
      status: :completed,
      completed_at: Time.current,
      metadata: @transcript.metadata.merge(session_end_params[:metadata] || {})
    )

    broadcast_session_event("session_ended", {
      transcript_id: @transcript.id,
      session_id: @transcript.source_session_id,
      message_count: @transcript.messages.count,
      duration: @transcript.completed_at - @transcript.started_at
    })

    render json: {
      success: true,
      transcript_id: @transcript.id,
      message_count: @transcript.messages.count
    }
  end

  # POST /api/v1/claude_code/stream_event
  def stream_event
    case stream_params[:event_type]
    when "user_prompt_submit"
      handle_user_message
    when "pre_tool_use"
      handle_tool_planning
    when "post_tool_use"
      handle_tool_result
    when "assistant_response"
      handle_assistant_message
    else
      render json: {error: "Unknown event type: #{stream_params[:event_type]}"}, status: :bad_request
      return
    end

    render json: {success: true, message_id: @message&.id}
  end

  private

  def find_or_create_agent
    @agent = current_user.agents.find_or_create_by(
      name: "Claude Code",
      client: "claude_code"
    ) do |agent|
      agent.origin = :blank_slate
      agent.llm_model = "claude-3-5-sonnet"
      agent.metadata = {
        source: "claude_code",
        auto_created: true
      }
    end
  end

  def find_or_create_transcript
    session_id = params[:session_id] || stream_params[:session_id]

    @transcript = @agent.transcripts.find_or_create_by(
      source_session_id: session_id
    ) do |transcript|
      transcript.source = "claude_code"
      transcript.status = :active
      transcript.started_at = Time.current
    end
  end

  def handle_user_message
    @message = @transcript.messages.create!(
      agent: @agent,
      role: :user,
      content: stream_params[:payload][:prompt_text],
      sequence: next_sequence,
      timestamp: parse_timestamp(stream_params[:payload][:timestamp]),
      metadata: {
        event_type: "user_prompt_submit",
        hook_data: stream_params[:payload]
      }
    )

    broadcast_message_event("user_message", @message)
  end

  def handle_tool_planning
    @message = @transcript.messages.create!(
      agent: @agent,
      role: :assistant,
      thinking: stream_params[:payload][:reasoning] || "Planning to use #{stream_params[:payload][:tool_name]}",
      content: "Using tool: #{stream_params[:payload][:tool_name]}",
      sequence: next_sequence,
      timestamp: Time.current,
      metadata: {
        event_type: "pre_tool_use",
        tool_name: stream_params[:payload][:tool_name],
        tool_input: stream_params[:payload][:tool_input],
        hook_data: stream_params[:payload]
      }
    )

    broadcast_message_event("tool_planning", @message)
  end

  def handle_tool_result
    @message = @transcript.messages.create!(
      agent: @agent,
      role: :tool_result,
      content: stream_params[:payload][:tool_output],
      sequence: next_sequence,
      timestamp: Time.current,
      metadata: {
        event_type: "post_tool_use",
        tool_name: stream_params[:payload][:tool_name],
        tool_input: stream_params[:payload][:tool_input],
        hook_data: stream_params[:payload]
      }
    )

    broadcast_message_event("tool_result", @message)
  end

  def handle_assistant_message
    @message = @transcript.messages.create!(
      agent: @agent,
      role: :assistant,
      content: stream_params[:payload][:response_text],
      thinking: stream_params[:payload][:thinking],
      sequence: next_sequence,
      timestamp: parse_timestamp(stream_params[:payload][:timestamp]),
      metadata: {
        event_type: "assistant_response",
        hook_data: stream_params[:payload]
      }
    )

    broadcast_message_event("assistant_message", @message)
  end

  def next_sequence
    (@transcript.messages.maximum(:sequence) || 0) + 1
  end

  def parse_timestamp(timestamp_str)
    return Time.current unless timestamp_str
    Time.zone.parse(timestamp_str)
  rescue ArgumentError
    Time.current
  end

  def broadcast_message_event(event_name, message)
    ActionCable.server.broadcast("transcript_#{@transcript.id}", {
      event: event_name,
      message: {
        id: message.id,
        role: message.role,
        content: message.content,
        thinking: message.thinking,
        sequence: message.sequence,
        timestamp: message.timestamp,
        metadata: message.metadata
      }
    })
  end

  def broadcast_session_event(event_name, data)
    ActionCable.server.broadcast("transcript_#{@transcript.id}", {
      event: event_name,
      data: data
    })
  end

  def stream_params
    params.require(:claude_code).permit(
      :event_type, :session_id, :timestamp,
      payload: {}
    )
  end

  def session_start_params
    params.require(:claude_code).permit(
      :session_id,
      metadata: {}
    )
  end

  def session_end_params
    params.require(:claude_code).permit(
      :session_id,
      metadata: {}
    )
  end
end
