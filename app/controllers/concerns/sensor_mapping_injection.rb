# Injects InfluxDB mapping defaults and constraints into sensor survey JSON.
# For fixed-field sources (senec, forecast), measurement and field are locked
# and determined by the collector configuration.
module SensorMappingInjection
  extend ActiveSupport::Concern

  # Sources where the InfluxDB field and measurement are determined by the collector
  FIXED_FIELD_SOURCES = %w[senec forecast].freeze

  # Default measurements when no collector config exists yet
  DEFAULT_MEASUREMENTS = {
    'senec' => 'SENEC',
    'forecast' => 'forecast',
  }.freeze

  private

  def inject_mapping_defaults!(survey)
    mapping_page = survey['pages']&.find { |p| p['name'] == 'p_mapping' }
    return unless mapping_page

    fixed = SensorRegistry.sources_for(sensor_name) & FIXED_FIELD_SOURCES
    inject_mapping_descriptions!(mapping_page, fixed) if fixed.any?
    mapping_page['elements'].each { |el| inject_mapping_element_defaults!(el) }
  end

  def inject_mapping_element_defaults!(element)
    fixed = SensorRegistry.sources_for(sensor_name) & FIXED_FIELD_SOURCES

    case element['name']
    when 'measurement'
      element['defaultValueExpression'] = measurement_expression
      inject_fixed_constraints!(element, fixed, measurement_expression_for(fixed)) if fixed.any?
    when 'field'
      element['defaultValueExpression'] = field_expression
      inject_fixed_constraints!(element, fixed, field_expression) if fixed.any?
    end
  end

  # Replace the static page description with conditional hints
  def inject_mapping_descriptions!(mapping_page, fixed_sources)
    mapping_page.delete('description')

    fixed_if = fixed_sources.map { |s| "{source} = '#{s}'" }.join(' or ')
    editable_if = fixed_sources.map { |s| "{source} != '#{s}'" }.join(' and ')
    labels = fixed_sources.map { |s| Configurations::SurveysController::SOURCE_LABELS.dig(s, 'de') }.join('/')

    mapping_page['elements'].unshift(
      mapping_hint('mapping_hint_fixed', fixed_if, **fixed_hint_texts(labels)),
      mapping_hint('mapping_hint_editable', editable_if, **editable_hint_texts),
    )
  end

  def mapping_hint(name, condition, texts:)
    { 'type' => 'html', 'name' => name, 'visibleIf' => condition, 'html' => texts }
  end

  def fixed_hint_texts(labels)
    {
      texts: {
        'de' => "<div class='alert alert-info'>Measurement und Field werden vom #{labels} " \
                'vorgegeben. Das Measurement kann in der Collector-Konfiguration angepasst werden.</div>',
        'default' => "<div class='alert alert-info'>Measurement and field are determined by the #{labels}. " \
                     'The measurement can be adjusted in the collector configuration.</div>',
      },
    }
  end

  def editable_hint_texts
    {
      texts: {
        'de' => "<div class='alert alert-warning'>⚠️ Measurement und Field legen fest, wo die Daten " \
                'in InfluxDB gespeichert werden. Eine nachträgliche Änderung ist kaum möglich.</div>',
        'default' => "<div class='alert alert-warning'>⚠️ Measurement and field determine where data " \
                     'is stored in InfluxDB. Changing these later is very difficult.</div>',
      },
    }
  end

  # Lock a mapping element when a fixed-field source is selected
  def inject_fixed_constraints!(element, fixed_sources, expression)
    element['enableIf'] = fixed_sources.map { |s| "{source} != '#{s}'" }.join(' and ')
    element['setValueIf'] = fixed_sources.map { |s| "{source} = '#{s}'" }.join(' or ')
    element['setValueExpression'] = expression
  end

  # Measurement expression for fixed sources, reading from collector config
  def measurement_expression_for(fixed_sources)
    config = Configuration.current
    values = fixed_sources.map do |s|
      measurement = config.setting_data(s).measurement.presence || DEFAULT_MEASUREMENTS[s]
      [s, measurement]
    end
    values.reverse.reduce("''") do |fallback, (source, value)|
      "iif({source}='#{source}','#{value}',#{fallback})"
    end
  end

  def measurement_expression
    config = Configuration.current
    sources = SensorRegistry.sources_for(sensor_name)
    build_iif_expression(sources) do |s|
      if s.in?(FIXED_FIELD_SOURCES)
        config.setting_data(s).measurement.presence || DEFAULT_MEASUREMENTS[s]
      else
        SensorMappings.default_measurement(sensor_name, s)
      end
    end
  end

  def field_expression
    sources = SensorRegistry.sources_for(sensor_name)
    build_iif_expression(sources) { |s| SensorMappings.default_field(sensor_name, s) }
  end

  # Builds nested iif() expression: iif({source}='senec','SENEC',iif({source}='shelly','x',''))
  def build_iif_expression(sources, &)
    values = sources.map { |s| [s, yield(s)] }
    values.reverse.reduce("''") do |fallback, (source, value)|
      "iif({source}='#{source}','#{value}',#{fallback})"
    end
  end
end
