RSpec.describe Mqtt::MappingGraph do
  subject(:graph) { described_class.new(Configuration.current) }

  before do
    with_config_yaml(
      'sensors' => {
        'house_power' => { 'source' => 'mqtt', 'mqtt_topic' => 'h/p', 'mqtt_name' => 'house_power' },
        'wallbox_power' => { 'source' => 'mqtt', 'mqtt_topic' => 'w/p', 'mqtt_name' => 'wallbox_power' },
        'heatpump_power' => { 'source' => 'shelly' },
      },
      'mqtt' => {
        'mqtt_host' => 'broker.local',
        'mappings' => [
          # A calculated entry that reads both sensors
          { 'name' => 'base_load', 'formula' => '{house_power} - {wallbox_power}', 'measurement' => 'm',
            'field' => 'base_load' },
          # A second one, chained onto the first
          { 'name' => 'doubled', 'formula' => '{base_load} * 2', 'measurement' => 'm', 'field' => 'doubled' },
          # An ordinary topic without a name
          { 'topic' => 'x/y', 'measurement' => 'm', 'field' => 'x' },
        ],
      },
    )
  end

  describe '#names' do
    it 'collects the names of both kinds of entry' do
      expect(graph.names).to contain_exactly('house_power', 'wallbox_power', 'base_load', 'doubled')
    end
  end

  describe '#names_used_by_others' do
    it 'leaves out the name of the entry being edited' do
      expect(graph.names_used_by_others([:sensor, 'house_power']))
        .to contain_exactly('wallbox_power', 'base_load', 'doubled')
    end
  end

  describe '#referencable_from' do
    it 'offers every other name to an entry that nothing reads' do
      expect(graph.referencable_from([:topic, 2]))
        .to contain_exactly('house_power', 'wallbox_power', 'base_load', 'doubled')
    end

    # base_load reads house_power, and doubled reads base_load. Offering either
    # of them to house_power would close a cycle the collector refuses.
    it 'leaves out the readers of the entry, through the whole chain' do
      expect(graph.referencable_from([:sensor, 'house_power'])).to contain_exactly('wallbox_power')
    end

    it 'leaves out the entry itself and its direct reader' do
      expect(graph.referencable_from([:topic, 0])).to contain_exactly('house_power', 'wallbox_power')
    end

    it 'offers every name to an entry that does not exist yet' do
      expect(graph.referencable_from([:topic, nil]))
        .to contain_exactly('house_power', 'wallbox_power', 'base_load', 'doubled')
    end
  end

  describe '#dependents_of' do
    it 'names the entries whose formula reads the name' do
      expect(graph.dependents_of('house_power')).to contain_exactly('base_load')
    end

    it 'is empty for a name nothing reads' do
      expect(graph.dependents_of('doubled')).to be_empty
    end

    it 'is empty for a blank name' do
      expect(graph.dependents_of(nil)).to be_empty
    end
  end
end
