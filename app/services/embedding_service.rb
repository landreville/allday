class EmbeddingService
  def initialize
    @conn = Faraday.new(url: "https://api.openai.com") do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{Allday.embedding_api_key}"
    end
  end

  def embed(text)
    embed_batch([text]).first
  end

  def embed_batch(texts)
    response = @conn.post("/v1/embeddings") do |req|
      req.body = {
        model: Allday.embedding_model,
        input: texts
      }
    end

    raise "Embedding API error: #{response.status} #{response.body}" unless response.success?

    response.body["data"].map { |d| d["embedding"] }
  end
end
