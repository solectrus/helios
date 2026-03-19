module ApplicationHelper
  SENSOR_GROUP_ICONS = {
    inverter: 'fa-solar-panel',
    grid: 'fa-plug',
    battery: 'fa-car-battery',
    wallbox: 'fa-charging-station',
    car: 'fa-car',
    heatpump: 'fa-fan',
    forecast: 'fa-cloud-sun',
    custom: 'fa-gauge',
  }.freeze

  def sensor_group_icon(group)
    SENSOR_GROUP_ICONS[group.to_sym] || 'fa-circle-question'
  end
end
