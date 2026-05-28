RSpec.describe Orchestration::RedisCacheFlush do
  describe '.call' do
    it 'runs FLUSHALL and SAVE in a running container' do
      container = instance_double(Orchestration::Container, running?: true, name: 'solectrus-redis-1')
      allow(container).to receive(:exec).and_return([[], [], 0])

      expect(described_class.call(container)).to be(true)

      expect(container).to have_received(:exec).with(%w[redis-cli FLUSHALL])
      expect(container).to have_received(:exec).with(%w[redis-cli SAVE])
    end

    it 'returns false when the container is nil' do
      expect(described_class.call(nil)).to be(false)
    end

    it 'returns false when the container is not running' do
      container = instance_double(Orchestration::Container, running?: false)

      expect(described_class.call(container)).to be(false)
    end

    it 'returns false and skips SAVE when FLUSHALL fails' do
      container = instance_double(Orchestration::Container, running?: true, name: 'solectrus-redis-1')
      allow(container).to receive(:exec)
        .with(%w[redis-cli FLUSHALL])
        .and_return([[], ['error'], 1])

      expect(described_class.call(container)).to be(false)

      expect(container).not_to have_received(:exec).with(%w[redis-cli SAVE])
    end

    it 'returns false on Docker errors' do
      container = instance_double(Orchestration::Container, running?: true, name: 'solectrus-redis-1')
      allow(container).to receive(:exec).and_raise(Docker::Error::DockerError)

      expect(described_class.call(container)).to be(false)
    end
  end
end
