# frozen_string_literal: true

class MemorySearchService
  def initialize(user:, query:, agent_id: nil, skills: nil, limit: 10)
    @user = user
    @query = query
    @agent_id = agent_id
    @skills = skills
    @limit = limit.to_i.clamp(1, 100)
  end

  def search
    query_embedding = EmbeddingService.new.embed(@query)

    scope = MemoryChunk.joins(:agent).where(agents: {user_id: @user.id})
    scope = scope.where(agent_id: @agent_id) if @agent_id
    scope = scope.where("skills_demonstrated && ARRAY[?]::text[]", @skills) if @skills&.any?

    scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(@limit)
  end
end
