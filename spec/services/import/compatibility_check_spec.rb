RSpec.describe Import::CompatibilityCheck do
  # Builds a check from a real import scenario fixture (donor .bak files).
  def check_for(scenario)
    base = Rails.root.join('spec/fixtures/import_scenarios', scenario)
    compose = Compose::FILENAMES.lazy.map { |f| base.join("#{f}.bak") }.find(&:file?)
    reader = Import::StackReader.new(compose_path: compose, env_path: base.join('.env.bak'))
    described_class.new(reader)
  end

  describe '#unsupported_services' do
    it 'accepts a pure SOLECTRUS stack' do
      expect(check_for('with_custom_traefik').unsupported_services).to be_empty
    end

    it 'accepts dozzle as an allowlisted companion' do
      expect(check_for('real_world/user3').unsupported_services).to be_empty
    end

    it 'accepts senec-charger (SOLECTRUS, pending first-class support)' do
      expect(check_for('with_senec_charger').unsupported_services).to be_empty
    end

    it 'accepts tibber-collector (SOLECTRUS, pending first-class support)' do
      expect(check_for('with_tibber').unsupported_services).to be_empty
    end

    it 'flags foreign services while keeping dozzle (user6)' do
      names = check_for('real_world/user6').unsupported_services.pluck('service')
      expect(names).to contain_exactly('mosquitto', 'pgadmin')
    end

    it 'flags an unknown third-party image' do
      expect(check_for('with_unknown').unsupported_services)
        .to contain_exactly('service' => 'nginx', 'image' => 'nginx:alpine')
    end
  end

  describe '#call!' do
    it 'passes for a supported stack' do
      expect { check_for('real_world/user3').call! }.not_to raise_error
    end

    it 'raises UnsupportedServicesError naming the offending services' do
      expect { check_for('real_world/user6').call! }
        .to raise_error(Import::UnsupportedServicesError) do |error|
          expect(error.services.map { |s| s['service'] })
            .to contain_exactly('mosquitto', 'pgadmin')
        end
    end
  end
end
