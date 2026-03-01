class Transcript < ApplicationRecord
  belongs_to :agent
  has_many :messages, dependent: :destroy
  has_many :memory_chunks, dependent: :destroy

  enum :status, { active: 0, completed: 1 }

  validates :source, presence: true
  validates :status, presence: true
end
