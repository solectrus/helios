module Export
  class Env
    class Forecast < Section
      def call
        fcast = configuration.forecast
        return if fcast.forecast.blank?

        env.add_section('Forecast')
        if configuration.forecast_pvnode_v2?
          pvnode_v2_entries(fcast)
        else
          base_entries(fcast)
          roof_entries(fcast)
          provider_entries(fcast)
        end
        entry('INFLUX_MEASUREMENT_FORECAST', fcast.measurement.presence || 'forecast',
              'InfluxDB measurement name for forecasts')
      end

      private

      # pvnode API v2 is site-based: location and all PV strings live on the
      # pvnode site and are referenced by its ID, so HELIOS emits neither the
      # location nor the roof/extra-param variables (see
      # Configuration#forecast_pvnode_v2?).
      def pvnode_v2_entries(fcast)
        entry('FORECAST_PROVIDER', fcast.forecast, 'Forecast provider')
        entry('PVNODE_SITE_ID', fcast.forecast_pvnode_site_id,
              'pvnode site ID (enables the site-based API v2)')
        entry('PVNODE_APIKEY', fcast.forecast_pvnode_apikey, 'pvnode API key')
        pvnode_paid_entry(fcast)
      end

      def base_entries(fcast)
        entry('FORECAST_PROVIDER', fcast.forecast, 'Forecast provider')
        entry('FORECAST_LATITUDE', fcast.forecast_latitude, 'Solar panel latitude')
        entry('FORECAST_LONGITUDE', fcast.forecast_longitude, 'Solar panel longitude')
        optional_entry('FORECAST_INTERVAL',
                       ::Forecast::IntervalRules.emit_value(provider: fcast.forecast,
                                                            interval: fcast.forecast_interval),
                       'Forecast update interval in seconds')
        optional_base_entries(fcast)
      end

      def optional_base_entries(fcast)
        optional_entry('FORECAST_DAMPING_MORNING', fcast.forecast_damping_morning,
                       'Damping factor for morning hours')
        optional_entry('FORECAST_DAMPING_EVENING', fcast.forecast_damping_evening,
                       'Damping factor for evening hours')
        optional_entry('FORECAST_HORIZON', fcast.forecast_horizon, 'Forecast horizon in hours')
        optional_entry('FORECAST_INVERTER', fcast.forecast_inverter,
                       'Maximum inverter power in kW (forecast.solar caps the forecast at this value)')
      end

      def roof_entries(fcast)
        roofs = (fcast.forecast_roofs || 1).to_i
        if roofs > 1
          multi_roof_entries(fcast, roofs)
        else
          single_roof_entries(fcast)
        end
      end

      def single_roof_entries(fcast)
        entry('FORECAST_DECLINATION', fcast.forecast_declination1, 'Roof tilt angle')
        entry('FORECAST_AZIMUTH', azimuth_value(fcast, 1), azimuth_comment(fcast))
        entry('FORECAST_KWP', fcast.forecast_kwp1, 'System capacity in kWp')
      end

      def multi_roof_entries(fcast, roofs)
        entry('FORECAST_CONFIGURATIONS', roofs.to_s, 'Number of roof surfaces')
        roofs.times do |i|
          entry("FORECAST_#{i}_DECLINATION", fcast.send("forecast_declination#{i + 1}"),
                "Roof surface #{i + 1} tilt angle")
          entry("FORECAST_#{i}_AZIMUTH", azimuth_value(fcast, i + 1),
                "Roof surface #{i + 1} orientation (#{azimuth_range(fcast)})")
          entry("FORECAST_#{i}_KWP", fcast.send("forecast_kwp#{i + 1}"),
                "Roof surface #{i + 1} capacity in kWp")
        end
      end

      # Pv-Node uses azimuth from north (0..360); Forecast.Solar uses
      # azimuth from south (-180..180). The fields are stored separately so
      # bounds and hints match the provider.
      def azimuth_value(fcast, index)
        if fcast.forecast == 'pvnode'
          fcast.send("forecast_pvnode_azimuth#{index}")
        else
          fcast.send("forecast_azimuth#{index}")
        end
      end

      def azimuth_comment(fcast)
        "Roof orientation (#{azimuth_range(fcast)})"
      end

      def azimuth_range(fcast)
        if fcast.forecast == 'pvnode'
          '0=N, 90=E, 180=S, 270=W'
        else
          '-180=N, -90=E, 0=S, 90=W, 180=N'
        end
      end

      def provider_entries(fcast)
        case fcast.forecast
        when 'forecast.solar'
          if fcast.forecast_solar_apikey.present?
            entry('FORECAST_SOLAR_APIKEY', fcast.forecast_solar_apikey,
                  'Forecast.Solar API key')
          end
        when 'solcast'
          solcast_entries(fcast)
        when 'pvnode'
          pvnode_entries(fcast)
        end
      end

      def solcast_entries(fcast)
        roofs = (fcast.forecast_roofs || 1).to_i
        entry('SOLCAST_APIKEY', fcast.forecast_solcast_api_key, 'Solcast API key')
        entry('SOLCAST_SITE', fcast.forecast_solcast_id1, 'Solcast site ID')
        return unless roofs > 1

        entry('SOLCAST_0_SITE', fcast.forecast_solcast_id1, 'Solcast site 1 ID')
        entry('SOLCAST_1_SITE', fcast.forecast_solcast_id2, 'Solcast site 2 ID')
      end

      def pvnode_entries(fcast)
        entry('PVNODE_APIKEY', fcast.forecast_pvnode_apikey, 'pvnode API key')
        pvnode_paid_entry(fcast)
        if fcast.forecast_pvnode_extra_params.present?
          entry('PVNODE_EXTRA_PARAMS', fcast.forecast_pvnode_extra_params,
                'Additional pvnode parameters')
        end
        pvnode_per_roof_extra_params_entries(fcast)
      end

      # PVNODE_PAID is shared by the v1 and v2 emitters; only set for paid
      # accounts (the collector treats an absent value as the free tier).
      def pvnode_paid_entry(fcast)
        return unless pvnode_paid_plan?(fcast.forecast_pvnode_paid)

        entry('PVNODE_PAID', fcast.forecast_pvnode_paid,
              'pvnode paid plan — only set for paid accounts (true = Light, nowcast = Plus)')
      end

      def pvnode_paid_plan?(value)
        ::Forecast::PvnodeRules.paid_plan?(value)
      end

      def pvnode_per_roof_extra_params_entries(fcast)
        roofs = (fcast.forecast_roofs || 1).to_i
        roofs.times do |i|
          value = fcast.send("forecast_pvnode_extra_params#{i + 1}")
          next if value.blank?

          entry("PVNODE_#{i}_EXTRA_PARAMS", value,
                "Additional pvnode parameters for roof #{i + 1}")
        end
      end
    end
  end
end
