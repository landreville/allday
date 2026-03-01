# frozen_string_literal: true

require "rails_helper"

RSpec.describe TranscriptImporter do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:jsonl_path) { Rails.root.join("spec/fixtures/files/sample_transcript.jsonl") }
  let(:jsonl_content) { File.read(jsonl_path) }

  describe "#import" do
    it "creates a transcript with messages from JSONL content" do
      result = described_class.new(
        agent: agent,
        jsonl_content: jsonl_content,
        source: "claude-code",
        source_session_id: "test-session-1"
      ).import

      expect(result).to be_a(Transcript)
      expect(result).to be_persisted
      expect(result.status).to eq("completed")
      expect(result.messages.count).to eq(5)
    end

    it "extracts user messages" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      user_msgs = result.messages.where(role: :user)
      expect(user_msgs.count).to eq(1)
      expect(user_msgs.first.content).to include("login bug")
    end

    it "extracts assistant messages with thinking" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      assistant_msgs = result.messages.where(role: :assistant)
      expect(assistant_msgs.count).to eq(2)
      expect(assistant_msgs.first.thinking).to eq("Let me look at the login code")
      expect(assistant_msgs.first.content).to include("auth controller")
    end

    it "extracts tool_call messages" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      tool_msgs = result.messages.where(role: :tool_call)
      expect(tool_msgs.count).to eq(1)
      expect(tool_msgs.first.metadata).to include("tool_name" => "Read")
    end

    it "extracts tool_result messages" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      result_msgs = result.messages.where(role: :tool_result)
      expect(result_msgs.count).to eq(1)
    end

    it "assigns sequential sequence numbers" do
      result = described_class.new(agent: agent, jsonl_content: jsonl_content, source: "claude-code").import
      sequences = result.messages.pluck(:sequence)
      expect(sequences).to eq([1, 2, 3, 4, 5])
    end

    it "skips non-message JSONL lines" do
      content_with_extras = <<~JSONL
        {"type":"progress","data":{"type":"hook_progress"},"timestamp":"2026-03-01T10:00:00.000Z","uuid":"p1"}
        {"type":"user","message":{"role":"user","content":"Hello"},"timestamp":"2026-03-01T10:00:01.000Z","uuid":"u1","parentUuid":"p1"}
        {"type":"file-history-snapshot","messageId":"snap1","snapshot":{}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}],"model":"claude-sonnet-4-6"},"timestamp":"2026-03-01T10:00:02.000Z","uuid":"a1","parentUuid":"u1"}
      JSONL

      result = described_class.new(agent: agent, jsonl_content: content_with_extras, source: "claude-code").import
      expect(result.messages.count).to eq(2)
    end

    it "skips meta messages" do
      content_with_meta = <<~JSONL
        {"type":"user","message":{"role":"user","content":"internal stuff"},"isMeta":true,"timestamp":"2026-03-01T10:00:00.000Z","uuid":"m1"}
        {"type":"user","message":{"role":"user","content":"Hello"},"timestamp":"2026-03-01T10:00:01.000Z","uuid":"u1"}
      JSONL

      result = described_class.new(agent: agent, jsonl_content: content_with_meta, source: "claude-code").import
      expect(result.messages.count).to eq(1)
      expect(result.messages.first.content).to eq("Hello")
    end
  end
end
