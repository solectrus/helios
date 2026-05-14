module Surveys
  module Ingest
    class Survey < Base
      private

      def customize!(data)
        choices = DockerImages.choices(:INGEST)
        if choices
          inject_image_choices!(data, choices)
        else
          data['pages']&.reject! { |page| page['name'] == 'p_image' }
        end
      end

      def inject_image_choices!(data, choices)
        element = find_element(data, 'image')
        return unless element

        element['choices'] = choices.map do |choice|
          { 'value' => choice[:image], 'text' => self.class.localized(**choice[:label]) }
        end
      end
    end
  end
end
