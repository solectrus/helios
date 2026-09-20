module Surveys
  # The field that takes the address SOLECTRUS is reached at. Two surveys ask
  # for it, because the address means a different thing in each: the network
  # settings ask for the address on the local network, the reverse-proxy
  # settings ask for the domain an external proxy routes. One field behind
  # both, so the two can never name the machine differently.
  #
  # Whatever the question, the answer has to name the machine to others, so
  # both refuse the address that names it to itself. The rule lives in
  # HostAddress, the field validates it while it is typed, and the controller
  # refuses it again for a request that bypasses the form.
  module AppHostField
    private

    def apply_app_host_validator!(data)
      element = find_element(data, 'app_host')
      element['validators'] = [app_host_validator] if element
    end

    def app_host_validator
      {
        'type' => 'regex',
        'regex' => HostAddress::SURVEY_PATTERN,
        'caseInsensitive' => true,
        'text' => self.class.localized(
          en: 'This address names the machine to itself alone. Others do not reach SOLECTRUS at it.',
          de: 'Diese Adresse benennt den Rechner nur sich selbst gegenüber. ' \
              'Andere erreichen SOLECTRUS darüber nicht.',
        ),
      }
    end
  end
end
