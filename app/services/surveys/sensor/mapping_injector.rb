module Surveys
  module Sensor
    # Injects InfluxDB mapping defaults into the sensor survey. For
    # fixed-source collectors (senec, forecast), measurement and field are
    # dictated by the collector and normalized server-side on save, so the
    # mapping page is hidden entirely.
    class MappingInjector
      def initialize(sensor_name)
        @sensor_name = sensor_name
      end

      def call(survey)
        mapping_page = survey['pages']&.find { |p| p['name'] == 'p_mapping' }
        return unless mapping_page

        hide_for_fixed_sources!(mapping_page) if fixed_sources.any?
        mapping_page['elements'].each { |el| inject_element_defaults!(el) }
      end

      private

      attr_reader :sensor_name

      def fixed_sources
        SensorRegistry.sources_for(sensor_name) & SensorMappings::FIXED_SOURCES
      end

      def hide_for_fixed_sources!(mapping_page)
        mapping_page['visibleIf'] = fixed_sources.map { |s| "{source} != '#{s}'" }.join(' and ')
      end

      def inject_element_defaults!(element)
        case element['name']
        when 'measurement'
          element['defaultValueExpression'] = measurement_expression
        when 'field'
          element['defaultValueExpression'] = field_expression
        end
      end

      def measurement_expression
        build_iif_expression(SensorRegistry.sources_for(sensor_name)) do |source|
          if source.in?(SensorMappings::FIXED_SOURCES)
            Configuration.current.setting_data(source).measurement.presence ||
              SensorMappings::DEFAULT_MEASUREMENTS[source]
          else
            SensorMappings.default_measurement(sensor_name, source)
          end
        end
      end

      def field_expression
        build_iif_expression(SensorRegistry.sources_for(sensor_name)) do |source|
          SensorMappings.default_field(sensor_name, source)
        end
      end

      # Builds nested iif() expression: iif({source}='senec','SENEC',iif({source}='shelly','x',''))
      def build_iif_expression(sources, &)
        values = sources.map { |s| [s, yield(s)] }
        values.reverse.reduce("''") do |fallback, (source, value)|
          "iif({source}='#{source}','#{value}',#{fallback})"
        end
      end
    end
  end
end
