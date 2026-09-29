# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
  passw
  email
  secret
  token
  _key
  apikey
  codeword
  crypt
  salt
  certificate
  otp
  ssn
  cvv
  cvc
]

# The surveys post their answers as one JSON string in `data`, which the
# key-based filters above never look into. Filter the parsed answers with the
# same keys instead.
survey_answers_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters.dup)
Rails.application.config.filter_parameters << lambda do |key, value|
  next unless key.to_s == 'data' && value.is_a?(String)

  answers = JSON.parse(value)
  value.replace(answers.is_a?(Hash) ? survey_answers_filter.filter(answers).to_json : '[FILTERED]')
rescue JSON::ParserError
  value.replace('[FILTERED]')
end
