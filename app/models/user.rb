# frozen_string_literal: true

class User < ApplicationRecord
  has_many :agents, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: {case_sensitive: false}
  validates :api_key, presence: true, uniqueness: true

  before_validation :generate_api_key, on: :create

  private

  def generate_api_key
    self.api_key = SecureRandom.hex(32) if api_key.blank?
  end
end
