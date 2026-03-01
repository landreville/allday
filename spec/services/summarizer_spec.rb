# frozen_string_literal: true

require "rails_helper"

RSpec.describe Summarizer do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent, status: :completed) }

  before do
    create(:message, transcript: transcript, agent: agent, role: :user, content: "Help me set up OAuth", sequence: 1)
    create(:message, transcript: transcript, agent: agent, role: :assistant,
      content: "I'll help with OAuth. Let me check the auth controller.", sequence: 2)
    create(:message, transcript: transcript, agent: agent, role: :user, content: "Now let's add rate limiting",
      sequence: 3)
    create(:message, transcript: transcript, agent: agent, role: :assistant,
      content: "I'll add rate limiting using Rack::Attack.", sequence: 4)
  end

  describe "#summarize" do
    it "creates memory chunks from transcript messages" do
      llm_response = {
        "chunks" => [
          {
            "topic" => "OAuth setup",
            "summary" => "Helped set up OAuth authentication in the auth controller.",
            "skills" => %w[oauth authentication rails],
            "message_range_start" => 1,
            "message_range_end" => 2
          },
          {
            "topic" => "Rate limiting",
            "summary" => "Added rate limiting using Rack::Attack middleware.",
            "skills" => %w[rate-limiting rack security],
            "message_range_start" => 3,
            "message_range_end" => 4
          }
        ]
      }

      anthropic_client = instance_double("Anthropic::Client")
      messages_resource = double("messages_resource")
      allow(Anthropic::Client).to receive(:new).and_return(anthropic_client)
      allow(anthropic_client).to receive(:messages).and_return(messages_resource)

      content_block = double("content_block", text: llm_response.to_json)
      allow(content_block).to receive(:respond_to?).with(:text).and_return(true)
      response = double("response", content: [content_block])
      allow(messages_resource).to receive(:create).and_return(response)

      embedding_service = instance_double(EmbeddingService)
      allow(EmbeddingService).to receive(:new).and_return(embedding_service)
      allow(embedding_service).to receive(:embed_batch).and_return([
        Array.new(1536) { 0.1 },
        Array.new(1536) { 0.2 }
      ])

      result = described_class.new(transcript).summarize

      expect(result.length).to eq(2)
      expect(result.first.topic).to eq("OAuth setup")
      expect(result.first.skills_demonstrated).to include("oauth")
      expect(result.first.embedding).to be_present
      expect(result.first.message_range_start).to eq(1)
      expect(result.last.topic).to eq("Rate limiting")
    end

    it "replaces existing memory chunks on re-summarization" do
      create(:memory_chunk, transcript: transcript, agent: agent, topic: "old topic")

      llm_response = {
        "chunks" => [{
          "topic" => "New topic",
          "summary" => "New summary.",
          "skills" => ["new"],
          "message_range_start" => 1,
          "message_range_end" => 4
        }]
      }

      anthropic_client = instance_double("Anthropic::Client")
      messages_resource = double("messages_resource")
      allow(Anthropic::Client).to receive(:new).and_return(anthropic_client)
      allow(anthropic_client).to receive(:messages).and_return(messages_resource)
      content_block = double("content_block", text: llm_response.to_json)
      allow(content_block).to receive(:respond_to?).with(:text).and_return(true)
      response = double("response", content: [content_block])
      allow(messages_resource).to receive(:create).and_return(response)

      embedding_service = instance_double(EmbeddingService)
      allow(EmbeddingService).to receive(:new).and_return(embedding_service)
      allow(embedding_service).to receive(:embed_batch).and_return([Array.new(1536) { 0.5 }])

      described_class.new(transcript).summarize

      expect(transcript.memory_chunks.count).to eq(1)
      expect(transcript.memory_chunks.first.topic).to eq("New topic")
    end
  end
end
