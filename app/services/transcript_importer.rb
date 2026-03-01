class TranscriptImporter
  def initialize(agent:, jsonl_content:, source:, source_session_id: nil, metadata: {})
    @agent = agent
    @jsonl_content = jsonl_content
    @source = source
    @source_session_id = source_session_id
    @metadata = metadata
  end

  def import
    transcript = @agent.transcripts.create!(
      source: @source,
      source_session_id: @source_session_id,
      status: :completed,
      started_at: nil,
      completed_at: Time.current,
      metadata: @metadata || {}
    )

    sequence = 0

    @jsonl_content.each_line do |line|
      line = line.strip
      next if line.empty?

      entry = JSON.parse(line)
      next unless %w[user assistant].include?(entry["type"])
      next if entry["isMeta"]

      message_data = entry["message"]
      next unless message_data

      parsed_messages = parse_entry(message_data)
      next if parsed_messages.nil? || parsed_messages.empty?

      parsed_messages.each do |msg_attrs|
        sequence += 1
        transcript.messages.create!(
          agent_id: @agent.id,
          sequence: sequence,
          timestamp: entry["timestamp"],
          **msg_attrs
        )
      end
    end

    transcript.reload
    transcript
  end

  private

  def parse_entry(message_data)
    role = message_data["role"]
    content = message_data["content"]

    case role
    when "user"
      parse_user_content(content)
    when "assistant"
      parse_assistant_content(content, message_data)
    end
  end

  def parse_user_content(content)
    if content.is_a?(String)
      [{ role: :user, content: content }]
    elsif content.is_a?(Array)
      content.filter_map do |block|
        case block["type"]
        when "tool_result"
          text = if block["content"].is_a?(String)
            block["content"]
          else
            block["content"]&.filter_map { |c| c["text"] }&.join("\n")
          end
          { role: :tool_result, content: text, metadata: { tool_use_id: block["tool_use_id"] } }
        when "text"
          { role: :user, content: block["text"] }
        end
      end
    end
  end

  def parse_assistant_content(content, message_data)
    return [{ role: :assistant, content: content }] if content.is_a?(String)
    return nil unless content.is_a?(Array)

    thinking = nil
    text_parts = []
    tool_calls = []

    content.each do |block|
      case block["type"]
      when "thinking" then thinking = block["thinking"]
      when "text" then text_parts << block["text"]
      when "tool_use" then tool_calls << block
      end
    end

    results = []

    if text_parts.any?
      results << {
        role: :assistant,
        content: text_parts.join("\n"),
        thinking: thinking,
        metadata: { model: message_data["model"] }.compact
      }
    end

    tool_calls.each do |tc|
      results << {
        role: :tool_call,
        content: tc["input"]&.to_json,
        thinking: (thinking if results.empty?),
        metadata: { tool_name: tc["name"], tool_use_id: tc["id"], model: message_data["model"] }.compact
      }
    end

    # Thinking-only (no text, no tools)
    if results.empty? && thinking
      results << { role: :assistant, content: nil, thinking: thinking, metadata: { model: message_data["model"] }.compact }
    end

    results.presence
  end
end
