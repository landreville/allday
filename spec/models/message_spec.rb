# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message, type: :model do
  subject { build(:message) }

  describe "validations" do
    it { should validate_presence_of(:role) }
    it { should validate_presence_of(:sequence) }
    it { should define_enum_for(:role).with_values(user: 0, assistant: 1, system: 2, tool_call: 3, tool_result: 4) }
  end

  describe "associations" do
    it { should belong_to(:transcript) }
    it { should belong_to(:agent) }
  end

  describe "ordering" do
    it "has a default scope ordered by sequence" do
      transcript = create(:transcript)
      msg3 = create(:message, transcript: transcript, agent: transcript.agent, sequence: 3)
      msg1 = create(:message, transcript: transcript, agent: transcript.agent, sequence: 1)
      msg2 = create(:message, transcript: transcript, agent: transcript.agent, sequence: 2)

      expect(transcript.messages.to_a).to eq([msg1, msg2, msg3])
    end
  end
end
