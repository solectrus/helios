module Surveys
  # Template Method base for surveys. Subclasses live in
  # `app/services/surveys/<survey_id>/` next to a `survey.json` sidecar
  # and may override `valid?` (gating) and/or `customize!` (mutation).
  class Base
    def self.survey_id
      name.split('::')[-2].underscore
    end

    # Builds a SurveyJS-style locale hash. SurveyJS expects `default` for the
    # English fallback plus per-language overrides keyed by ISO code.
    def self.localized(en:, de:) # rubocop:disable Naming/MethodParameterName
      { 'default' => en, 'de' => de }
    end

    def initialize(sensor_name: nil)
      @sensor_name = sensor_name
    end

    def call
      return nil unless valid?

      path = json_path
      return nil unless path.exist?

      data = JSON.parse(path.read)
      customize!(data)
      data
    end

    private

    attr_reader :sensor_name

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
  end
end
