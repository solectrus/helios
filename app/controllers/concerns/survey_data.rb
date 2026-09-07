# The surveys post their answers as one JSON string in `data`. A body that is
# not JSON is a client bug, not a validation error, so it is answered with 400
# and the action stops.
module SurveyData
  extend ActiveSupport::Concern

  private

  def survey_data
    JSON.parse(params.require(:data))
  rescue JSON::ParserError
    head(:bad_request)
    nil
  end
end
