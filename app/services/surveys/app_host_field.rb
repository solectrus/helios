module Surveys
  # The field that takes the address SOLECTRUS is reached at.
  #
  # The address has to name the machine to others, so the field refuses the
  # address that names it to itself. The rule lives in HostAddress, the field
  # validates it while it is typed, and the controller refuses it again for a
  # request that bypasses the form.
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
