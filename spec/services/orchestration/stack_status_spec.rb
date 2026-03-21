RSpec.describe Orchestration::StackStatus do
  before { described_class.instance.reset! }

  describe '#overall' do
    context 'when not initialized' do
      before do
        # Stub refresh! to avoid real Docker calls, just mark as initialized
        allow(described_class.instance).to receive(:refresh!) do
          described_class.instance.instance_variable_get(:@initialized).make_true
        end
      end

      it 'triggers refresh on first call' do
        described_class.overall
        expect(described_class.instance).to have_received(:refresh!)
      end
    end

    context 'when initialized with no services' do
      before do
        described_class.instance.instance_variable_get(:@initialized).make_true
      end

      it 'returns :stopped' do
        expect(described_class.overall).to eq(:stopped)
      end
    end
  end

  describe '#update and compute_overall' do
    before do
      described_class.instance.instance_variable_get(:@initialized).make_true
      allow(Orchestration::StatusBarBroadcaster).to receive(:new)
        .and_return(instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil))
    end

    it 'returns :ok when all services are running' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :running)

      expect(described_class.overall).to eq(:ok)
    end

    it 'returns :stopped when all services are stopped' do
      described_class.update('postgresql', :stopped)
      described_class.update('redis', :stopped)

      expect(described_class.overall).to eq(:stopped)
    end

    it 'returns :error when any service has error' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :error)

      expect(described_class.overall).to eq(:error)
    end

    it 'returns :starting when any service is starting' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :starting)

      expect(described_class.overall).to eq(:starting)
    end

    it 'returns :partial when some services are stopped' do
      described_class.update('postgresql', :running)
      described_class.update('redis', :stopped)

      expect(described_class.overall).to eq(:partial)
    end
  end

  describe '#services_settling?' do
    before do
      allow(Orchestration::StatusBarBroadcaster).to receive(:new)
        .and_return(instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil))
    end

    it 'returns true when a service is starting' do
      described_class.update('postgresql', :starting)

      expect(described_class.services_settling?).to be true
    end

    it 'returns false when all services are running' do
      described_class.update('postgresql', :running)

      expect(described_class.services_settling?).to be false
    end
  end

  describe '#reset!' do
    before do
      allow(Orchestration::StatusBarBroadcaster).to receive(:new)
        .and_return(instance_double(Orchestration::StatusBarBroadcaster, broadcast: nil))
      described_class.update('postgresql', :running)
    end

    it 'clears all state' do
      described_class.reset!

      initialized = described_class.instance.instance_variable_get(:@initialized)
      expect(initialized.true?).to be false
    end
  end
end
