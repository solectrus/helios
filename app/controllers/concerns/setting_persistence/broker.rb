# The part of SettingPersistence that speaks for the broker HELIOS runs
# itself. One survey writes two sections here, and the rules that split the
# payload between them are of no use to any other survey.
#
# Named for the broker rather than for MQTT: a constant `Mqtt` under this
# module would shadow the top-level one for every controller that includes
# SettingPersistence (Mqtt::MappingGraph among them).
module SettingPersistence
  module Broker
    private

    # The MQTT survey drives the collector plus, where the box is ticked, the
    # broker HELIOS runs itself. The broker's fields BORROWED_FIELDS routes
    # into `mosquitto`; blanking them drops that section down to its storage
    # path (see #blank_mosquitto!).
    # `mappings` never travels through the survey, so it is carried over by
    # hand — Configuration#update replaces the whole section.
    def persist_mqtt(data)
      answer = data.delete('broker_external')
      # SurveyJS sends prefilled values back even where it renders no question,
      # so an unticked box still carries the flag of the previous run. Drop it,
      # or HELIOS keeps the broker running, now with blanked credentials.
      data.delete('broker_managed')

      apply_broker_answer!(data, answer)

      mappings = @configuration.mqtt_topics
      data['mappings'] = mappings if mappings.any?
      preserve_software_owned_image!(data)
      @configuration.update('mqtt', data)
    end

    # `false` means the box is ticked and HELIOS runs the broker, `true` means
    # a broker of the user. A missing answer is no answer: the payload never
    # carried the question, so this save speaks for the broker in neither
    # direction and leaves what runs today alone (see #ignore_senec_charger!
    # for the same rule on the charger).
    def apply_broker_answer!(data, answer)
      return ignore_broker!(data) if answer.nil?

      if answer == false
        data['broker_managed'] = true
        # The survey hides the foreign broker while HELIOS runs its own, but
        # SurveyJS keeps the answers of a hidden question in the payload. Drop
        # them, or the credentials of the previous broker stay in config.yaml.
        # These fields belong to the `mqtt` section itself, which
        # Configuration#update replaces as a whole, so removing the key is what
        # empties them.
        data.except!(*ConfigSchema::MQTT_CONNECTION_FIELDS)
        normalize_mosquitto_fields!(data)
      else
        blank_mosquitto!(data)
      end
    end

    # Carry the stored flag over, and drop the broker fields from the payload
    # so store_borrowed_fields! writes none of them. Blanking would delete a
    # login the payload was never asked about.
    def ignore_broker!(data)
      data['broker_managed'] = true if @configuration.mqtt_broker_managed?
      data.except!(*Configuration::MOSQUITTO_SURVEY_FIELDS)
    end

    # SurveyJS drops an emptied answer from the payload instead of sending an
    # empty one, and Configuration#store_borrowed_fields! skips a field the
    # payload does not carry. So name every broker field: a cleared password
    # arrives as a missing key and must still remove the stored one.
    def normalize_mosquitto_fields!(data)
      Configuration::MOSQUITTO_SURVEY_FIELDS.each { |field| data[field] = data[field].presence }

      # A password without a user name cannot become a login: the broker needs
      # both halves to write its password file. Keeping the password would show
      # a login in the UI that no device can use, because `allow_anonymous
      # false` stands either way and a broker without a password file turns
      # every client away. The survey shows the password field only once a
      # user name is there, and this is where a payload from anywhere else
      # meets the same rule.
      data['password'] = nil if data['username'].blank?
    end

    # The section goes, except for the storage path (see
    # Configuration#drop_mosquitto!): blanking the survey's fields alone would
    # leave `image` behind, and the next managed run would start on a stale
    # image. The payload has to drop them too, or store_borrowed_fields! would
    # write the answers SurveyJS echoes back for the hidden broker questions
    # into a fresh `mosquitto`.
    def blank_mosquitto!(data)
      data.except!(*Configuration::MOSQUITTO_SURVEY_FIELDS)
      @configuration.drop_mosquitto!
    end
  end
end
