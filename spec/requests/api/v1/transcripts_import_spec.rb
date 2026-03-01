# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Transcripts Import", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:jsonl_content) { Rails.root.join("spec/fixtures/files/sample_transcript.jsonl").read }

  describe "POST /api/v1/transcripts/import" do
    it "imports a JSONL transcript" do
      post "/api/v1/transcripts/import", headers: auth_headers(user), params: {
        agent_id: agent.id,
        source: "claude-code",
        source_session_id: "session-abc",
        jsonl: jsonl_content
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["message_count"]).to be > 0
    end

    it "returns 422 for invalid agent" do
      post "/api/v1/transcripts/import", headers: auth_headers(user), params: {
        agent_id: 999_999,
        source: "claude-code",
        jsonl: jsonl_content
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
