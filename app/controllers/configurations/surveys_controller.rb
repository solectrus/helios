module Configurations
  class SurveysController < ApplicationController
    SOURCE_LABELS = {
      'senec' => { 'de' => 'SENEC-Collector', 'default' => 'SENEC Collector' },
      'shelly' => { 'de' => 'Shelly-Collector', 'default' => 'Shelly Collector' },
      'mqtt' => { 'de' => 'MQTT-Collector', 'default' => 'MQTT Collector' },
      'forecast' => { 'de' => 'Forecast-Collector', 'default' => 'Forecast Collector' },
      'smart_home' => { 'de' => 'Extern (Smart Home)', 'default' => 'External (Smart Home)' },
    }.freeze

    def show
      survey_id = resolve_survey_id
      return head(:not_found) unless survey_id

      path = Rails.root.join("config/surveys/#{survey_id}.json")
      return head(:not_found) unless path.exist?

      survey = JSON.parse(path.read)
      customize_sensor_survey!(survey) if sensor_survey?
      render json: survey
    end

    private

    def survey_setting
      params[:id]
    end

    def sensor_name
      params[:sensor]
    end

    # Resolve which survey JSON file to load
    def resolve_survey_id
      return survey_setting if Configuration.valid?(survey_setting)
      return 'sensor' if sensor_survey?

      nil
    end

    def sensor_survey?
      survey_setting == 'sensor' && sensor_name.present? && SensorRegistry.valid?(sensor_name)
    end

    def custom_power_sensor?
      sensor_name&.start_with?('custom_power_')
    end

    def invert_power_relevant?
      sensor_name&.start_with?('battery_') || sensor_name == 'inverter_power'
    end

    def customize_sensor_survey!(survey)
      inject_sensor_title!(survey)
      inject_source_choices!(survey)
      inject_mapping_defaults!(survey)
      if custom_power_sensor?
        inject_name_page!(survey)
        inject_house_power_page!(survey)
      elsif invert_power_relevant?
        inject_shelly_invert_power!(survey)
      end
    end

    def inject_sensor_title!(survey)
      survey['title'] = sensor_name.upcase
    end

    # Dynamically set the source choices based on the sensor's available sources
    def inject_source_choices!(survey)
      sources = SensorRegistry.sources_for(sensor_name)
      return if sources.empty?

      source_element = find_source_element(survey)
      return unless source_element

      source_element['choices'] = sources.map { |s| source_choice(s) }
    end

    def find_source_element(survey)
      survey['pages']&.each do |page|
        page['elements']&.each do |element|
          return element if element['name'] == 'source'
        end
      end
      nil
    end

    def source_choice(source)
      { 'value' => source, 'text' => SOURCE_LABELS[source] || source }
    end

    def inject_mapping_defaults!(survey)
      mapping_page = survey['pages']&.find { |p| p['name'] == 'p_mapping' }
      return unless mapping_page

      mapping_page['elements'].each do |element|
        case element['name']
        when 'measurement'
          element['defaultValueExpression'] = measurement_expression
        when 'field'
          element['defaultValueExpression'] = field_expression
        end
      end
    end

    def measurement_expression
      sources = SensorRegistry.sources_for(sensor_name)
      build_iif_expression(sources) { |s| SensorMappings.default_measurement(sensor_name, s) }
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

    def inject_name_page!(survey)
      name_page = {
        'name' => 'p_name',
        'title' => { 'de' => 'Anzeigename', 'default' => 'Display name' },
        'elements' => [name_element],
      }
      survey['pages'] = [survey['pages'].first, name_page, *survey['pages'][1..]]
    end

    def name_element
      {
        'type' => 'text',
        'name' => 'name',
        'title' => {
          'de' => 'Name für diesen Verbraucher',
          'default' => 'Name for this consumer',
        },
        'description' => {
          'de' => 'Wird als InfluxDB-Measurement und im Dashboard angezeigt',
          'default' => 'Used as InfluxDB measurement and displayed in the dashboard',
        },
        'isRequired' => true,
        'placeholder' => { 'de' => 'z.B. Kühlschrank', 'default' => 'e.g. Fridge' },
      }
    end

    def inject_shelly_invert_power!(survey)
      shelly_local_page = survey['pages']&.find { |p| p['name'] == 'p_shelly_local' }
      return unless shelly_local_page

      shelly_local_page['elements'] << {
        'type' => 'boolean',
        'name' => 'shelly_invert_power',
        'title' => {
          'de' => 'Leistungswerte invertieren',
          'default' => 'Invert power values',
        },
        'description' => {
          'de' => 'Aktiviere dies, wenn die Leistungswerte mit negativem Vorzeichen gemeldet werden',
          'default' => 'Enable if power values are reported with negative sign',
        },
        'defaultValue' => false,
      }
    end

    def inject_house_power_page!(survey)
      survey['pages'] << {
        'name' => 'p_house_power',
        'visibleIf' => "{source} = 'shelly' or {source} = 'mqtt' or {source} = 'smart_home'",
        'title' => { 'de' => 'Hausverbrauch', 'default' => 'House power' },
        'elements' => [house_power_element],
      }
    end

    def house_power_element
      {
        'type' => 'boolean',
        'name' => 'exclude_from_house_power',
        'title' => {
          'de' => 'Aus Hausverbrauch herausrechnen',
          'default' => 'Deduct from house power',
        },
        'description' => {
          'de' => 'Korrigiert den Hausverbrauch, indem der Verbrauch dieses Sensors abgezogen wird',
          'default' => "Corrects house power by deducting this sensor's consumption",
        },
        'defaultValue' => false,
      }
    end
  end
end
