require "rails_helper"

RSpec.describe Agent, type: :model do
  subject { build(:agent) }

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:origin) }
    it { should define_enum_for(:origin).with_values(blank_slate: 0, continued: 1, branched: 2) }
  end

  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:parent).class_name("Agent").optional }
    it { should have_many(:children).class_name("Agent").with_foreign_key(:parent_id) }
    it { should have_many(:transcripts).dependent(:destroy) }

    it "has many memory_chunks" do
      pending "MemoryChunk model not yet created (Task 6)"
      should have_many(:memory_chunks).dependent(:destroy)
    end
  end

  describe "branching" do
    it "requires parent when origin is branched" do
      agent = build(:agent, origin: :branched, parent: nil)
      expect(agent).not_to be_valid
      expect(agent.errors[:parent_id]).to include("is required for branched agents")
    end

    it "does not require parent for blank_slate" do
      agent = build(:agent, origin: :blank_slate, parent: nil)
      expect(agent).to be_valid
    end
  end
end
