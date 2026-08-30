module Surveys
  # Template Method base for surveys. Subclasses live in
  # `app/services/surveys/<survey_id>/` next to a `survey.json` sidecar
  # and may override `valid?` (gating) and/or `customize!` (mutation).
  class Base
    # `visibleIfMode` marker a survey JSON may attach to a page or element to
    # gate it by deployment mode. The marker is stripped from the rendered
    # JSON. SurveyJS' own `visibleIf` only sees fields within the same survey,
    # so mode (which lives in its own section) needs server-side resolution.
    MODE_PREDICATES = {
      'full' => ->(mode) { mode == ConfigSchema::MODE_FULL },
      'collectors_only' => ->(mode) { mode == ConfigSchema::MODE_COLLECTORS_ONLY },
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

    # Strips pages and elements whose server-side marker doesn't hold. The
    # marker is removed from the rendered JSON either way so it never reaches
    # SurveyJS.
    def apply_marker_visibility!(data)
      mode = Configuration.current.mode
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
