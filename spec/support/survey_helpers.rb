module SurveyHelpers
  # Returns the first element with the given `name` across all survey pages.
  def find_survey_element(survey, name)
    Array(survey['pages']).each do |page|
      Array(page['elements']).each do |element|
        return element if element['name'] == name
      end
    end
    nil
  end

  # Names of the survey's top-level pages.
  def section_names(survey)
    Array(survey['pages']).pluck('name')
  end
end

RSpec.configure do |config|
  config.include SurveyHelpers, file_path: %r{spec/services/surveys/}
end
