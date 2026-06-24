module Forecast
  # Shared pvnode export rules for the .env value emitter (Export::Env::Forecast)
  # and the compose env-key list (Export::Services::ForecastCollector).
  module PvnodeRules
    # Canonical env-var key set for the site-based API v2, consumed by the
    # compose service's environment list. Location and all PV strings live on
    # the pvnode site and are referenced by the site ID, so none of the
    # location/roof/extra-param variables are exported. PVNODE_PAID is appended
    # only for paid accounts; see #v2_env_keys.
    V2_BASE_KEYS = %w[FORECAST_PROVIDER PVNODE_SITE_ID PVNODE_APIKEY].freeze

    module_function

    # PVNODE_PAID is only set for paid accounts; the collector treats an absent
    # value as the free tier.
    def paid_plan?(value)
      value.present? && value.to_s != 'false'
    end

    # The full, ordered v2 env-var key list for the given PVNODE_PAID value.
    def v2_env_keys(paid_value)
      keys = V2_BASE_KEYS.dup
      keys << 'PVNODE_PAID' if paid_plan?(paid_value)
      keys
    end
  end
end
