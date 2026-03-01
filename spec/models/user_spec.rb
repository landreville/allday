# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  subject { build(:user) }

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_uniqueness_of(:api_key) }

    it "validates api_key presence (callback auto-generates when blank)" do
      user = User.new(name: "Test", email: "test@example.com", api_key: nil)
      # The before_validation callback fills in api_key, so it should be valid
      expect(user).to be_valid
      # Verify the presence validator is defined on api_key
      validator_classes = User.validators_on(:api_key).map(&:class)
      expect(validator_classes).to include(ActiveRecord::Validations::PresenceValidator)
    end
  end

  describe "associations" do
    it { should have_many(:agents).dependent(:destroy) }
  end

  describe "#generate_api_key" do
    it "generates a unique api_key before validation if blank" do
      user = User.new(name: "Test", email: "test@example.com")
      user.valid?
      expect(user.api_key).to be_present
      expect(user.api_key.length).to be >= 32
    end
  end
end
