# frozen_string_literal: true

class MemoryChunk < ApplicationRecord
  belongs_to :transcript
  belongs_to :agent

  has_neighbors :embedding

  validates :topic, presence: true
  validates :summary, presence: true
end
