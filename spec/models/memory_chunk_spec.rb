require "rails_helper"

RSpec.describe MemoryChunk, type: :model do
  subject { build(:memory_chunk) }

  describe "validations" do
    it { should validate_presence_of(:topic) }
    it { should validate_presence_of(:summary) }
  end

  describe "associations" do
    it { should belong_to(:transcript) }
    it { should belong_to(:agent) }
  end

  describe "vector search" do
    it "finds nearest neighbors by embedding" do
      agent = create(:agent)
      transcript = create(:transcript, agent: agent)

      chunk1 = create(:memory_chunk, transcript: transcript, agent: agent,
        topic: "auth", embedding: [1.0] + Array.new(1535, 0.0))
      chunk2 = create(:memory_chunk, transcript: transcript, agent: agent,
        topic: "database", embedding: [0.0, 1.0] + Array.new(1534, 0.0))

      results = MemoryChunk.nearest_neighbors(:embedding, [1.0, 0.1] + Array.new(1534, 0.0), distance: "cosine").first(5)
      expect(results.first).to eq(chunk1)
    end
  end
end
