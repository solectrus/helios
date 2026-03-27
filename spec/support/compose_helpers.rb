module ComposeHelpers
  def mock_service_collection(services) # rubocop:disable Metrics/AbcSize
    instance_double(Compose::ServiceCollection).tap do |collection|
      allow(collection).to receive(:each) { |&block| services.each(&block) }
      allow(collection).to receive(:reject) { |&block| services.reject(&block) }
      allow(collection).to receive(:all?) { |&block| services.all?(&block) }
      allow(collection).to receive(:to_set) { |&block| services.to_set(&block) }
      allow(collection).to receive(:map) { |&block| services.map(&block) }
      allow(collection).to receive_messages(empty?: services.empty?, sorted: services)
    end
  end
end

RSpec.configure do |config|
  config.include ComposeHelpers
end
