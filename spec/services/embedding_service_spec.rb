require "rails_helper"

RSpec.describe EmbeddingService do
  describe "#embed" do
    it "returns a vector of floats for a text input" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with(body: hash_including("model" => "text-embedding-3-small", "input" => ["test text"]))
        .to_return(
          status: 200,
          body: {
            data: [{ embedding: Array.new(1536) { |i| i * 0.001 } }]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = described_class.new.embed("test text")

      expect(result).to be_an(Array)
      expect(result.length).to eq(1536)
      expect(result.first).to be_a(Float)
    end
  end

  describe "#embed_batch" do
    it "returns vectors for multiple texts" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(
          status: 200,
          body: {
            data: [
              { embedding: Array.new(1536) { 0.1 } },
              { embedding: Array.new(1536) { 0.2 } }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      results = described_class.new.embed_batch(["text one", "text two"])

      expect(results.length).to eq(2)
      expect(results.first.length).to eq(1536)
    end
  end
end
