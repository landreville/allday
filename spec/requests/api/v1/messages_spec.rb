require "rails_helper"

RSpec.describe "Api::V1::Messages", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent, status: :active) }

  describe "POST /api/v1/transcripts/:transcript_id/messages" do
    it "appends a message to the transcript" do
      post "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: {
        message: { role: "user", content: "Hello there", sequence: 1 }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["role"]).to eq("user")
      expect(body["content"]).to eq("Hello there")
      expect(body["sequence"]).to eq(1)
    end

    it "appends an assistant message with thinking" do
      post "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: {
        message: { role: "assistant", content: "Hi!", thinking: "User said hello, I should respond.", sequence: 2 }
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["thinking"]).to eq("User said hello, I should respond.")
    end

    it "rejects messages on completed transcripts" do
      transcript.update!(status: :completed, completed_at: Time.current)

      post "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: {
        message: { role: "user", content: "Too late", sequence: 1 }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/transcripts/:transcript_id/messages" do
    it "returns messages ordered by sequence" do
      create(:message, transcript: transcript, agent: agent, role: :assistant, content: "Second", sequence: 2)
      create(:message, transcript: transcript, agent: agent, role: :user, content: "First", sequence: 1)

      get "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |m| m["content"] }).to eq(["First", "Second"])
    end

    it "paginates results" do
      25.times do |i|
        create(:message, transcript: transcript, agent: agent, sequence: i + 1, content: "msg #{i + 1}")
      end

      get "/api/v1/transcripts/#{transcript.id}/messages", headers: auth_headers(user), params: { page: 1, per_page: 10 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(10)
      expect(body.first["content"]).to eq("msg 1")
    end
  end
end
