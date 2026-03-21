RSpec.describe Orchestration::Event do
  def build_raw_event(type: 'container', action: 'start', service_name: 'postgresql')
    actor = Data.define(:attributes).new(
      attributes: { 'com.docker.compose.service' => service_name },
    )
    Data.define(:type, :action, :actor).new(type:, action:, actor:)
  end

  let(:event) { described_class.new(build_raw_event) }

  describe '#relevant?' do
    it 'returns true for a relevant container event' do
      expect(event).to be_relevant
    end

    it 'returns false for non-container events' do
      event = described_class.new(build_raw_event(type: 'network'))
      expect(event).not_to be_relevant
    end

    it 'returns false when service_name is blank' do
      event = described_class.new(build_raw_event(service_name: nil))
      expect(event).not_to be_relevant
    end

    %w[create start stop die destroy].each do |action|
      it "returns true for '#{action}' action" do
        event = described_class.new(build_raw_event(action:))
        expect(event).to be_relevant
      end
    end

    it 'returns true for health_status actions' do
      event = described_class.new(build_raw_event(action: 'health_status: healthy'))
      expect(event).to be_relevant
    end

    it 'returns false for irrelevant actions' do
      event = described_class.new(build_raw_event(action: 'attach'))
      expect(event).not_to be_relevant
    end
  end

  describe '#service_name' do
    it 'extracts from Docker Compose label' do
      expect(event.service_name).to eq('postgresql')
    end

    it 'returns nil when actor is nil' do
      raw = Data.define(:type, :action, :actor).new(
        type: 'container', action: 'start', actor: nil,
      )
      event = described_class.new(raw)
      expect(event.service_name).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      expect(event.to_h).to eq(
        type: 'container',
        action: 'start',
        service_name: 'postgresql',
      )
    end
  end

  describe '#inspect' do
    it 'returns a readable string' do
      expect(event.inspect).to eq(
        '#<Orchestration::Event container:start service=postgresql>',
      )
    end
  end
end
