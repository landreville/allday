require "rails_helper"

RSpec.describe Transcript, type: :model do
  subject { build(:transcript) }

  describe "validations" do
    it { should validate_presence_of(:source) }
    it { should validate_presence_of(:status) }
    it { should define_enum_for(:status).with_values(active: 0, completed: 1) }
  end

  describe "associations" do
    it { should belong_to(:agent) }
    it { should have_many(:messages).dependent(:destroy) }

    it "has many memory_chunks" do
      pending "MemoryChunk model not yet created (Task 6)"
      should have_many(:memory_chunks).dependent(:destroy)
    end
  end
end
