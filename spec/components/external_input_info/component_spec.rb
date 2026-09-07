RSpec.describe ExternalInputInfo::Component, type: :component do
  it 'stays hidden without external sensors' do
    expect(described_class.new(configuration: Configuration.current).render?).to be(false)
  end

  it 'counts the sensors fed from outside the stack' do
    Configuration.current.update_sensor('house_power', { 'source' => 'external' })
    component = described_class.new(configuration: Configuration.current)

    expect(component.render?).to be(true)
    expect(component.sensor_count).to eq(1)
  end
end
