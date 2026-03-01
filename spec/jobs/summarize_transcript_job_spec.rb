require "rails_helper"

RSpec.describe SummarizeTranscriptJob, type: :job do
  let(:user) { create(:user) }
  let(:agent) { create(:agent, user: user) }
  let(:transcript) { create(:transcript, agent: agent, status: :completed) }

  it "calls Summarizer for the transcript" do
    summarizer = instance_double(Summarizer)
    allow(Summarizer).to receive(:new).with(transcript).and_return(summarizer)
    expect(summarizer).to receive(:summarize)

    described_class.perform_now(transcript.id)
  end

  it "skips non-existent transcripts" do
    expect { described_class.perform_now(999999) }.not_to raise_error
  end

  it "skips active transcripts" do
    transcript.update!(status: :active)
    expect(Summarizer).not_to receive(:new)
    described_class.perform_now(transcript.id)
  end
end
