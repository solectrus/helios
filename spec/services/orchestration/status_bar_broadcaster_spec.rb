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

    # Regression: the events listener, ComposeJob and request threads broadcast
    # concurrently. When a thread that read the older status finished rendering
    # after a thread that read the newer one, its stale HTML won and the bar was
    # stuck on "starting" until a full page reload.
    it 'never publishes stale HTML after a newer broadcast' do
      status = Concurrent::AtomicReference.new('starting')
      published = Concurrent::Array.new

      reading_old_status = Queue.new

      # The thread that read the *old* status renders slowest, so unsynchronized
      # it would publish last and win.
      allow(ApplicationController).to receive(:render) do
        html = status.get
        if html == 'starting'
          reading_old_status << true
          sleep 0.3
        end
        html
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*, **kwargs|
        published << kwargs[:html]
      end

      # rubocop:disable ThreadSafety/NewThread -- the race is the subject here
      slow = Thread.new { described_class.new.broadcast }
      reading_old_status.pop
      status.set('ok')
      fast = Thread.new { described_class.new.broadcast }
      # rubocop:enable ThreadSafety/NewThread
      [slow, fast].each(&:join)

      expect(published.last).to eq('ok')
    end
  end
end
