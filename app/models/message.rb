class Message < ApplicationRecord
  belongs_to :transcript
  belongs_to :agent

  enum :role, { user: 0, assistant: 1, system: 2, tool_call: 3, tool_result: 4 }

  validates :role, presence: true
  validates :sequence, presence: true

  default_scope { order(:sequence) }
end
