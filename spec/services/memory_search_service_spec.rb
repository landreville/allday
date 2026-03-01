require "rails_helper"

RSpec.describe MemorySearchService do
  let(:user) { create(:user) }
  let(:agent1) { create(:agent, user: user, name: "auth-agent") }
  let(:agent2) { create(:agent, user: user, name: "db-agent") }
  let(:transcript1) { create(:transcript, agent: agent1) }
  let(:transcript2) { create(:transcript, agent: agent2) }

  before do
    create(:memory_chunk, agent: agent1, transcript: transcript1,
      topic: "OAuth implementation",
      summary: "Implemented OAuth2 with PKCE flow",
      skills_demonstrated: ["oauth", "security"],
      embedding: [1.0] + Array.new(1535, 0.0))

    create(:memory_chunk, agent: agent2, transcript: transcript2,
      topic: "Database optimization",
      summary: "Optimized slow queries",
      skills_demonstrated: ["postgresql", "performance"],
      embedding: [0.0, 1.0] + Array.new(1534, 0.0))

    allow_any_instance_of(EmbeddingService).to receive(:embed)
      .and_return([0.9] + Array.new(1535, 0.0))
  end

  it "returns memory chunks ranked by similarity" do
    results = described_class.new(user: user, query: "oauth authentication").search

    expect(results.first.topic).to eq("OAuth implementation")
  end

  it "filters by agent_id" do
    results = described_class.new(user: user, query: "anything", agent_id: agent2.id).search

    expect(results.map(&:topic)).to eq(["Database optimization"])
  end

  it "filters by skills" do
    results = described_class.new(user: user, query: "anything", skills: ["postgresql"]).search

    expect(results.map(&:topic)).to eq(["Database optimization"])
  end

  it "respects limit" do
    results = described_class.new(user: user, query: "anything", limit: 1).search
    expect(results.length).to eq(1)
  end
end
