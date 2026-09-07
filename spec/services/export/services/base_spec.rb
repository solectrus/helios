RSpec.describe Export::Services::Base do
  it 'demands a name and a comment, and defaults the rest to "not managed"' do
    expect { described_class.service_name }.to raise_error(NotImplementedError)
    expect { described_class.comment }.to raise_error(NotImplementedError)
    expect(described_class.config_keys).to be_nil
    expect(described_class.volume_env_key).to be_nil
    expect(described_class).not_to be_persistent
  end

  describe '.config_keys' do
    # Every declared path must resolve against a real config.yaml section,
    # otherwise in-place image updates and storage paths break silently.
    Export::Compose::SERVICE_ORDER.each do |service_class|
      it "resolves to a configuration section for #{service_class.service_name}" do
        keys = service_class.config_keys
        next if keys.nil?

        node = Configuration.current.public_send(keys.first)
        expect(node).not_to be_nil

        keys[1..].each do |key|
          node = node.public_send(key)
          expect(node).not_to be_nil
        end
      end
    end
  end
end
