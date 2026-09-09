module Surveys
  module SystemGeneral
    class Survey < Base
      private

      def customize!(data)
        element = find_element(data, 'timezone')
        return unless element

        element['choices'] = timezone_choices
      end

      # Rails curates the tz database down to the zones people actually pick.
      # That list stays short enough to scroll through, unlike the 500-odd raw
      # identifiers, and the offset in front of each one groups them the way
      # somebody looking for their own zone expects. It is the zone's standard
      # offset, so the labels stay put when daylight saving time starts.
      def timezone_choices
        curated_zones.map do |zone|
          identifier = zone.tzinfo.name

          { 'value' => identifier, 'text' => "(UTC#{zone.formatted_offset}) #{identifier}" }
        end
      end

      # Rails lists some zones twice, under two city names ("Bern" and
      # "Zurich" are both Europe/Zurich), which would put the same value in
      # the field twice. Sorting by identifier rather than by those city names
      # also keeps each offset's entries in the order they are labelled in.
      def curated_zones
        zones = ActiveSupport::TimeZone.all
        zones += [current_zone] if current_zone

        zones.uniq { |zone| zone.tzinfo.name }.sort_by { |zone| [zone.utc_offset, zone.tzinfo.name] }
      end

      # A configuration imported from an existing installation can carry a
      # zone outside the curated set, and the field must still show it.
      def current_zone
        identifier = Configuration.current.system.timezone.presence
        return unless identifier
        return if ActiveSupport::TimeZone.all.any? { |zone| zone.tzinfo.name == identifier }

        ActiveSupport::TimeZone[identifier]
      end
    end
  end
end
