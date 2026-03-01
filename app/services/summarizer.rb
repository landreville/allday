# frozen_string_literal: true

class Summarizer
  SYSTEM_PROMPT = <<~PROMPT
    You are a conversation analyst. Given a transcript of messages between a user and an AI assistant, identify distinct topics/tasks discussed and produce a JSON summary.

    For each distinct topic, produce:
    - "topic": a short label (3-8 words) describing what was done
    - "summary": 2-3 paragraphs describing what was accomplished, decisions made, problems encountered, and solutions found
    - "skills": an array of skill/technology tags demonstrated (e.g., "postgresql", "debugging", "oauth")
    - "message_range_start": the sequence number of the first message in this topic
    - "message_range_end": the sequence number of the last message in this topic

    Return ONLY valid JSON in this format:
    {
      "chunks": [
        {
          "topic": "...",
          "summary": "...",
          "skills": ["..."],
          "message_range_start": 1,
          "message_range_end": 5
        }
      ]
    }
  PROMPT

  def initialize(transcript)
    @transcript = transcript
  end

  def summarize
    messages = @transcript.messages.select(:role, :content, :thinking, :sequence)
    return [] if messages.empty?

    # Delete existing chunks for idempotency
    @transcript.memory_chunks.destroy_all

    # Build conversation text for LLM
    conversation_text = messages.map do |msg|
      parts = ["[#{msg.sequence}] #{msg.role}:"]
      parts << "(thinking: #{msg.thinking})" if msg.thinking.present?
      parts << msg.content.to_s
      parts.join(" ")
    end.join("\n\n")

    # Call LLM for summarization
    client = Anthropic::Client.new(api_key: Allday.anthropic_api_key)
    response = client.messages.create(
      model: Allday.summarization_model,
      max_tokens: 4096,
      system_: SYSTEM_PROMPT,
      messages: [{role: "user", content: conversation_text}]
    )

    json_text = response.content.find { |c| c.respond_to?(:text) }&.text
    parsed = JSON.parse(json_text)
    chunks_data = parsed["chunks"] || []

    return [] if chunks_data.empty?

    # Generate embeddings for all summaries at once
    summaries = chunks_data.map { |c| "#{c["topic"]}: #{c["summary"]}" }
    embeddings = EmbeddingService.new.embed_batch(summaries)

    # Create memory chunks
    chunks_data.each_with_index.map do |chunk_data, i|
      @transcript.memory_chunks.create!(
        agent_id: @transcript.agent_id,
        topic: chunk_data["topic"],
        summary: chunk_data["summary"],
        embedding: embeddings[i],
        skills_demonstrated: chunk_data["skills"] || [],
        message_range_start: chunk_data["message_range_start"],
        message_range_end: chunk_data["message_range_end"]
      )
    end
  end
end
