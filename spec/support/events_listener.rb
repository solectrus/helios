# `connect '/cable'` runs ApplicationCable::Connection#connect, which reports a
# subscriber and starts a real EventsListener with two background threads.
# Nothing stopped them again, so the scheduler thread outlived the example that
# started it and kept calling StackStatus.refresh! inside later ones. There
# `Compose.load` is a double that never expected the call, and the thread died
# with a mock error that failed the whole parallel run while every example
# still passed.
RSpec.configure do |config|
  config.after do
    Orchestration::EventsListener.stop if Orchestration::EventsListener.running?
  end
end
