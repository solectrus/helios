RSpec.describe ExternalInputInfo::Component, type: :component do
  it 'stands on the screen dimmed while no sensor is fed that way' do
    component = described_class.new(configuration: Configuration.current)

    expect(component.sensor_count).to eq(0)
    expect(component.dimmed?).to be(true)
  end

  it 'counts the sensors fed from outside the stack' do
    Configuration.current.update_sensor('house_power', { 'source' => 'external' })
    component = described_class.new(configuration: Configuration.current)

    expect(component.sensor_count).to eq(1)
    expect(component.dimmed?).to be(false)
  end
end
