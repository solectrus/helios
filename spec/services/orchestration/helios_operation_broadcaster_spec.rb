RSpec.describe Orchestration::HeliosOperationBroadcaster do
  before do
    allow(BackupRunner).to receive(:invalidate_in_progress_cache!)
    allow(RestoreRunner).to receive(:invalidate_in_progress_cache!)
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_to)
  end

  describe '.broadcast!' do
    it 'refreshes the status bar and the backups page' do
      broadcaster = instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil)
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(broadcaster)

      described_class.broadcast!

      expect(broadcaster).to have_received(:broadcast)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to).with('backups')
    end

    # The listener knows which locale the connected browser uses, so the
    # rendered status bar has to be built in it rather than in the default.
    it 'renders in the locale it is given' do
      broadcaster = instance_double(Orchestration::StatusBarBroadcaster)
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_return(broadcaster)
      seen = nil
      allow(broadcaster).to receive(:broadcast) { seen = I18n.locale }

      described_class.broadcast!(locale: :de)

      expect(seen).to eq(:de)
      expect(I18n.locale).to eq(I18n.default_locale)
    end

    # Called from ensure blocks of background threads: a failure here must
    # never mask the operation that just finished.
    it 'swallows a failing broadcast' do
      allow(Orchestration::StatusBarBroadcaster).to receive(:new).and_raise(StandardError, 'no cable')

      expect { described_class.broadcast! }.not_to raise_error
    end
  end
end
