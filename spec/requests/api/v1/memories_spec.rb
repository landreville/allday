# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Memories", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent) }

  before do
    create(:memory_chunk, agent: agent, transcript: transcript,
      topic: "auth work", embedding: Array.new(1536) { 0.1 })

    allow_any_instance_of(EmbeddingService).to receive(:embed)
      .and_return(Array.new(1536) { 0.1 })
  end

  describe "GET /api/v1/memories/search" do
    it "returns search results" do
      get "/api/v1/memories/search", headers: auth_headers(user), params: {query: "authentication"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["topic"]).to eq("auth work")
      expect(body.first["agent_name"]).to be_present
    end

    it "returns 400 without query" do
      get "/api/v1/memories/search", headers: auth_headers(user)
      expect(response).to have_http_status(:bad_request)
    end
  end
end
