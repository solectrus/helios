module Surveys
  module ReverseProxy
    class Survey < Base
      # The address bar of the browser answers the address question only while
      # no reverse proxy is in play: it then carries the address of this
      # machine, which is what the field takes. Behind either proxy the field
      # takes a domain, and the bar names it nowhere.
      #
      # This form asks for the mode and for the address in one run, so the
      # offer names the answer it depends on instead of reading the stored mode
      # here. The client makes the offer while the chosen mode holds, and
      # withdraws it again when the mode changes to one that takes a domain.
      BROWSER_HOST_OFFER = {
        'question' => 'app_host',
        'while' => { 'question' => 'mode', 'values' => ['none'] },
      }.freeze

      private

      def customize!(data)
        apply_app_host_validator!(data)
        data['offerBrowserHost'] = BROWSER_HOST_OFFER
      end

      # The address has to name the machine to others, whatever the mode, so the
      # field refuses the address that names it to itself. The rule lives in
      # HostAddress, the field validates it while it is typed, and the
      # controller refuses it again for a request that bypasses the form.
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
end
