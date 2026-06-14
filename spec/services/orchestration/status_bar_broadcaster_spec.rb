RSpec.describe Orchestration::StatusBarBroadcaster do
  describe '#broadcast' do
    it 'replaces the status-bar target on the status_bar stream' do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      described_class.new.broadcast

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with('status_bar', target: 'status-bar', html: kind_of(String))
        .at_least(:once)
    end

    # A broadcast renders with the default locale but reaches clients of either
    # language, so it must ship every locale WITHOUT the `hidden` hint —
    # otherwise the text would be hidden for every client whose locale differs
    # from the default until the per-client CSS corrects it. (Regression for the
    # blank status bar after starting a single service.)
    it 'ships both locales unhidden so either language stays visible' do
      captured = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*, **kwargs|
        captured = kwargs[:html]
      end

      described_class.new.broadcast

      expect(captured).to include('data-locale="en"')
      expect(captured).to include('data-locale="de"')
      expect(captured).not_to match(/data-locale="(de|en)" hidden/)
    end
  end
end
