# frozen_string_literal: true

module Allday
  mattr_accessor :embedding_api_key
  mattr_accessor :embedding_model
  mattr_accessor :embedding_dimensions
  mattr_accessor :summarization_model
  mattr_accessor :anthropic_api_key

  self.embedding_api_key = ENV["OPENAI_API_KEY"]
  self.embedding_model = ENV.fetch("EMBEDDING_MODEL", "text-embedding-3-small")
  self.embedding_dimensions = ENV.fetch("EMBEDDING_DIMENSIONS", "1536").to_i
  self.summarization_model = ENV.fetch("SUMMARIZATION_MODEL", "claude-haiku-4-5-20251001")
  self.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
