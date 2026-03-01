# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Transcripts", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }

  describe "POST /api/v1/transcripts" do
    it "creates a new active transcript" do
      post "/api/v1/transcripts", headers: auth_headers(user), params: {
        transcript: {agent_id: agent.id, source: "claude-code", source_session_id: "abc-123"}
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("active")
      expect(body["source"]).to eq("claude-code")
      expect(body["agent_id"]).to eq(agent.id)
    end

    it "rejects transcript for another user's agent" do
      other_agent = create(:agent)
      post "/api/v1/transcripts", headers: auth_headers(user), params: {
        transcript: {agent_id: other_agent.id, source: "claude-code"}
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/transcripts/:id" do
    it "returns transcript metadata" do
      transcript = create(:transcript, agent: agent)

      get "/api/v1/transcripts/#{transcript.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(transcript.id)
    end
  end

  describe "PATCH /api/v1/transcripts/:id" do
    it "marks transcript as completed" do
      transcript = create(:transcript, agent: agent, status: :active)

      patch "/api/v1/transcripts/#{transcript.id}", headers: auth_headers(user), params: {
        transcript: {status: "completed"}
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["completed_at"]).to be_present
    end
  end
end
