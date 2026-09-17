module Surveys
  # Template Method base for surveys. Subclasses live in
  # `app/services/surveys/<survey_id>/` next to a `survey.json` sidecar
  # and may override `valid?` (gating) and/or `customize!` (mutation).
  class Base
    # Shown when a host port a survey asks for belongs to another service of
    # the stack (see #reserve_host_ports!).
    PORT_RESERVED_EN = 'This port belongs to another service. Reserved: %<ports>s'.freeze
    PORT_RESERVED_DE = 'Dieser Port gehört einem anderen Dienst. Reserviert: %<ports>s'.freeze

    # `visibleIfMode` marker a survey JSON may attach to a page or element to
    # gate it by deployment mode. The marker is stripped from the rendered
    # JSON. SurveyJS' own `visibleIf` only sees fields within the same survey,
    # so mode (which lives in its own section) needs server-side resolution.
    MODE_PREDICATES = {
      'full' => ->(mode) { mode == ConfigSchema::MODE_FULL },
      'not_collectors_only' => ->(mode) { mode != ConfigSchema::MODE_COLLECTORS_ONLY },
    }.freeze

    def self.survey_id
      name.split('::')[-2].underscore
    end

    # Builds a SurveyJS-style locale hash. SurveyJS expects `default` for the
    # English fallback plus per-language overrides keyed by ISO code.
    def self.localized(en:, de:) # rubocop:disable Naming/MethodParameterName
      { 'default' => en, 'de' => de }
    end

    # `index` identifies the entry of a list-backed survey (today only the
    # standalone MQTT mappings) so it can be told apart from its siblings, the
    # way `sensor_name` does for the sensor survey.
    def initialize(sensor_name: nil, index: nil)
      @sensor_name = sensor_name
      @index = index.presence&.to_i
    end

    def call
      return nil unless valid?

      path = json_path
      return nil unless path.exist?

      data = JSON.parse(path.read)
      apply_marker_visibility!(data)
      customize!(data)
      data
    end

    private

    attr_reader :sensor_name, :index

    # The configuration every survey reads its prefill and its gating from.
    # Memoized, because a survey asks for it on nearly every line it renders.
    def configuration
      @configuration ||= Configuration.current
    end

    def json_path
      Rails.root.join('app/services/surveys', self.class.survey_id, 'survey.json')
    end

    def valid?
      true
    end

    def customize!(_data); end

    def find_page(data, name)
      data['pages']&.find { |page| page['name'] == name }
    end

    def find_element(data, name)
      data['pages']&.each do |page|
        page['elements']&.each do |element|
          return element if element['name'] == name
        end
      end
      nil
    end

    def remove_element(data, name)
      data['pages']&.each do |page|
        page['elements']&.reject! { |element| element['name'] == name }
      end
    end

    # Refuses the host ports that other services of the stack hold. Two
    # services on one host port stop the stack, and the clash shows up only
    # when Docker starts it. The ports are reserved whether or not the
    # services that hold them run today, because they can be switched on
    # after the port is set.
    def reserve_host_ports!(data, name, ports)
      element = find_element(data, name)
      return if element.blank?

      ports = ports.map(&:to_i).uniq.sort
      element['validators'] = [
        {
          'type' => 'expression',
          'expression' => ports.map { |port| "{#{name}} <> #{port}" }.join(' and '),
          'text' => self.class.localized(
            en: format(PORT_RESERVED_EN, ports: ports.join(', ')),
            de: format(PORT_RESERVED_DE, ports: ports.join(', ')),
          ),
        },
      ]
    end

    # Strips pages and elements whose server-side marker doesn't hold. The
    # marker is removed from the rendered JSON either way so it never reaches
    # SurveyJS.
    def apply_marker_visibility!(data)
      mode = configuration.mode
      data['pages']&.reject! { |page| hidden_for_mode?(page, mode) }
      data['pages']&.each do |page|
        page['elements']&.reject! { |element| hidden_for_mode?(element, mode) }
      end
    end

    def hidden_for_mode?(node, mode)
      marker = node.delete('visibleIfMode')
      return false unless marker

      predicate = MODE_PREDICATES[marker]
      return false unless predicate

      !predicate.call(mode)
    end
  end
end
