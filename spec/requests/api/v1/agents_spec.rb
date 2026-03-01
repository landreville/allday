# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Agents", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/agents" do
    it "lists the user's agents" do
      create(:agent, user: user, name: "agent-1")
      create(:agent, user: user, name: "agent-2")
      create(:agent) # another user's agent

      get "/api/v1/agents", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
      expect(body.pluck("name")).to contain_exactly("agent-1", "agent-2")
    end
  end

  describe "POST /api/v1/agents" do
    it "creates a blank_slate agent" do
      post "/api/v1/agents", headers: auth_headers(user), params: {
        agent: {name: "my-agent", llm_model: "claude-opus-4-6", origin: "blank_slate"}
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("my-agent")
      expect(body["origin"]).to eq("blank_slate")
      expect(body["user_id"]).to eq(user.id)
    end

    it "creates a branched agent" do
      parent = create(:agent, user: user)
      post "/api/v1/agents", headers: auth_headers(user), params: {
        agent: {name: "child-agent", origin: "branched", parent_id: parent.id}
      }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["parent_id"]).to eq(parent.id)
    end

    it "returns 422 for invalid params" do
      post "/api/v1/agents", headers: auth_headers(user), params: {
        agent: {name: ""}
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/agents/:id" do
    it "returns the agent with lineage info" do
      parent = create(:agent, user: user, name: "parent")
      child = create(:agent, user: user, name: "child", origin: :branched, parent: parent)

      get "/api/v1/agents/#{child.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("child")
      expect(body["parent_id"]).to eq(parent.id)
    end

    it "returns 404 for another user's agent" do
      other_agent = create(:agent)
      get "/api/v1/agents/#{other_agent.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/agents/:id/memories" do
    it "returns the agent's memory chunks" do
      agent = create(:agent, user: user)
      transcript = create(:transcript, agent: agent)
      create(:memory_chunk, agent: agent, transcript: transcript, topic: "auth work")

      get "/api/v1/agents/#{agent.id}/memories", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["topic"]).to eq("auth work")
    end
  end

  describe "GET /api/v1/agents/:id/transcripts" do
    it "returns the agent's transcripts" do
      agent = create(:agent, user: user)
      create(:transcript, agent: agent, source: "claude-code")

      get "/api/v1/agents/#{agent.id}/transcripts", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["source"]).to eq("claude-code")
    end
  end
end
