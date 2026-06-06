RSpec.describe Import::ConfigurationImporter::SenecChargerExtractor do
  # Builds an extractor from a real import scenario fixture (donor .bak files).
  def extractor_for(scenario)
    base = Rails.root.join('spec/fixtures/import_scenarios', scenario)
    compose = Compose::FILENAMES.lazy.map { |f| base.join("#{f}.bak") }.find(&:file?)
    described_class.new(Import::StackReader.new(compose_path: compose, env_path: base.join('.env.bak')))
  end

  describe '#enabled?' do
    it 'extracts a charger whose prices, forecast and local battery are all there' do
      expect(extractor_for('with_senec_charger').enabled?).to be(true)
    end

    # user9 runs a real senec-charger against a battery its collector polls
    # through the cloud. The charger steers over the local API and knows no
    # adapter, so HELIOS has no address to configure it with and drops it.
    it 'drops a charger whose battery is polled through the cloud (user9)' do
      expect(extractor_for('real_world/user9').enabled?).to be(false)
    end

    it 'drops a charger with no prices to spend' do
      expect(extractor_for('with_tibber').enabled?).to be(false)
    end
  end

  describe '#section_data' do
    it 'imports dry_run as a boolean, not the raw env string' do
      # The survey renders dry_run as a SurveyJS boolean question, which matches
      # neither valueTrue nor valueFalse against a 'true' string — an imported
      # test mode would show as off and the next save would start real charging.
      expect(extractor_for('with_senec_charger').section_data['dry_run']).to be(false)
    end

    it 'captures the tuning and the pinned image' do
      expect(extractor_for('with_senec_charger').section_data).to include(
        'interval' => '3600',
        'price_max' => '70',
        'price_time_range' => '4',
        'forecast_threshold' => '20',
        'image' => 'ghcr.io/solectrus/senec-charger:latest',
      )
    end

    it 'returns nothing for a dropped charger' do
      expect(extractor_for('real_world/user9').section_data).to be_nil
    end

    it 'names the drop in the log rather than letting it pass unnoticed' do
      allow(Rails.logger).to receive(:info)
      extractor_for('real_world/user9').section_data

      expect(Rails.logger).to have_received(:info) do |&block|
        expect(block.call).to include('dropping senec-charger', 'polled through the cloud')
      end
    end
  end
end
