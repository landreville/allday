# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API Authentication", type: :request do
  describe "without authentication" do
    it "returns 401" do
      get "/api/v1/agents"
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("Invalid API key")
    end
  end

  describe "with valid API key" do
    it "returns 200" do
      user = create(:user)
      get "/api/v1/agents", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "with invalid API key" do
    it "returns 401" do
      get "/api/v1/agents", headers: {"Authorization" => "Bearer bad-key"}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
