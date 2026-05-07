module Surveys
  module Sensor
    # Injects InfluxDB mapping defaults and constraints into the sensor
    # survey. For fixed-source collectors (senec, forecast), measurement and
    # field are locked and derived from the collector configuration.
    class MappingInjector
      def initialize(sensor_name)
        @sensor_name = sensor_name
      end

      def call(survey)
        mapping_page = survey['pages']&.find { |p| p['name'] == 'p_mapping' }
        return unless mapping_page

        inject_descriptions!(mapping_page) if fixed_sources.any?
        mapping_page['elements'].each { |el| inject_element_defaults!(el) }
      end

      private

      attr_reader :sensor_name

      def fixed_sources
        SensorRegistry.sources_for(sensor_name) & SensorMappings::FIXED_SOURCES
      end

      def inject_element_defaults!(element)
        case element['name']
        when 'measurement'
          element['defaultValueExpression'] = measurement_expression
          inject_fixed_constraints!(element, measurement_expression_for_fixed) if fixed_sources.any?
        when 'field'
          element['defaultValueExpression'] = field_expression
          inject_fixed_constraints!(element, field_expression) if fixed_sources.any?
        end
      end

      def inject_descriptions!(mapping_page)
        mapping_page.delete('description')

        fixed_if = fixed_sources.map { |s| "{source} = '#{s}'" }.join(' or ')
        editable_if = fixed_sources.map { |s| "{source} != '#{s}'" }.join(' and ')
        labels = fixed_sources.map { |s| Survey::SOURCE_LABELS.dig(s, 'de') }.join('/')

        mapping_page['elements'].unshift(
          mapping_hint('mapping_hint_fixed', fixed_if, html: fixed_hint_html(labels)),
          mapping_hint('mapping_hint_editable', editable_if, html: editable_hint_html),
        )
      end

      def mapping_hint(name, condition, html:)
        { 'type' => 'html', 'name' => name, 'visibleIf' => condition, 'html' => html }
      end

      def fixed_hint_html(labels)
        Survey.localized(
          en: "<p class='sd-mapping-hint'>Measurement and field are determined by the #{labels}. " \
              'The measurement can be adjusted in the collector configuration.</p>',
          de: "<p class='sd-mapping-hint'>Measurement und Field werden vom #{labels} " \
              'vorgegeben. Das Measurement kann in der Collector-Konfiguration angepasst werden.</p>',
        )
      end

      def editable_hint_html
        Survey.localized(
          en: "<p class='sd-mapping-hint'>Measurement and field determine where data " \
              'is stored in InfluxDB. Changing these later is very difficult.</p>',
          de: "<p class='sd-mapping-hint'>Measurement und Field legen fest, wo die Daten " \
              'in InfluxDB gespeichert werden. Eine nachträgliche Änderung ist kaum möglich.</p>',
        )
      end

      def inject_fixed_constraints!(element, expression)
        element['enableIf'] = fixed_sources.map { |s| "{source} != '#{s}'" }.join(' and ')
        element['setValueIf'] = fixed_sources.map { |s| "{source} = '#{s}'" }.join(' or ')
        element['setValueExpression'] = expression
      end

      def measurement_expression_for_fixed
        build_iif_expression(fixed_sources) do |source|
          Configuration.current.setting_data(source).measurement.presence ||
            SensorMappings::DEFAULT_MEASUREMENTS[source]
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
