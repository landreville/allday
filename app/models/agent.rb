# frozen_string_literal: true

class Agent < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "Agent", optional: true
  has_many :children, class_name: "Agent", foreign_key: :parent_id, dependent: :nullify
  has_many :transcripts, dependent: :destroy
  has_many :memory_chunks, dependent: :destroy

  enum :origin, {blank_slate: 0, continued: 1, branched: 2}

  validates :name, presence: true
  validates :origin, presence: true
  validate :parent_required_for_branched

  # Scopes for different client types
  scope :claude_code, -> { where(client: 'claude_code') }

  private

  def parent_required_for_branched
    return unless branched? && parent_id.blank?

    errors.add(:parent_id, "is required for branched agents")
  end
end
