# The part of SettingPersistence that speaks for the SENEC charger. The prices
# survey writes the Tibber collector and the charger in one save, and the rules
# that split the payload between them are of no use to any other survey.
module SettingPersistence
  module Charger
    private

    # The prices survey drives two services through two UI-only flags. `enabled`
    # owns the Tibber collector (its own section), `charging` owns the SENEC
    # charger, whose fields BORROWED_FIELDS routes into `senec_charger`. Neither
    # flag is stored: whichever is off has its section's fields blanked, and
    # Configuration#update drops a section once its last field goes.
    def persist_tibber(data)
      enabled = data.delete('enabled') == true
      charging = data.delete('charging') == true

      data = {} unless enabled

      # Whether this survey run actually put the charging question on screen:
      # where the charger's dependencies don't hold, Surveys::Tibber::Survey
      # drops the charging pages server-side, so this save must not speak for
      # the charger in either direction (see #blank_senec_charger! /
      # #ignore_senec_charger!).
      if @configuration.senec_charger_configurable?
        blank_senec_charger!(data) unless enabled && charging
      else
        ignore_senec_charger!(data)
      end
      preserve_software_owned_image!(data) if enabled

      @configuration.update('tibber', data)
    end

    # Charging was offered and turned off (or the prices went with it): clear
    # the tuning. Configuration#update drops the section with its last field.
    def blank_senec_charger!(data)
      Configuration::SENEC_CHARGER_SURVEY_FIELDS.each { |field| data[field] = nil }
    end

    # Charging was never offered, so a missing `charging` flag means "not
    # asked", not "switched off". Drop the charger fields from the payload
    # instead: blanking would delete a tuning the user was never shown and
    # cannot re-enter until the dependency returns, while storing would let a
    # payload configure what the survey refused to render.
    def ignore_senec_charger!(data)
      data.except!(*Configuration::SENEC_CHARGER_SURVEY_FIELDS)
    end
  end
end
