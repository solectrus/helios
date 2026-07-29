RSpec.describe Orchestration::PowerSplitter::Recalculation do
  include ActiveSupport::Testing::TimeHelpers

  let(:container) do
    instance_double(Orchestration::Container, running?: true, name: 'solectrus-power-splitter-1')
  end

  before { allow(container).to receive(:kill) }

  after { Orchestration::PowerSplitter::State.clear_all }

  describe '.call' do
    it 'signals USR1 to a running container' do
      expect(described_class.call(container)).to be(true)

      expect(container).to have_received(:kill).with(signal: 'USR1')
    end

    it 'remembers when the recalculation was triggered' do
      freeze_time do
        described_class.call(container)

        expect(Orchestration::PowerSplitter::State.triggered_at).to eq(Time.current)
      end
    end

    it 'returns false when the container is nil' do
      expect(described_class.call(nil)).to be(false)
    end

    it 'returns false when the container is not running' do
      stopped = instance_double(Orchestration::Container, running?: false)

      expect(described_class.call(stopped)).to be(false)
    end

    it 'returns false on Docker errors' do
      allow(container).to receive(:kill).and_raise(Docker::Error::DockerError)

      expect(described_class.call(container)).to be(false)
      expect(Orchestration::PowerSplitter::State.triggered_at).to be_nil
    end
  end
end
