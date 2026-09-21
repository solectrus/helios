# senec_custom_measurement

A plain local SENEC installation whose user types their own measurement name
on the SENEC screen. The survey offers the field, so the answer is one a user
can give, and this is the only scenario that gives it.

What the scenario holds in place: the collector and every one of the sixteen
sensors name the same measurement.

    INFLUX_MEASUREMENT_SENEC=MY_SENEC
    INFLUX_SENSOR_INVERTER_POWER=MY_SENEC:inverter_power
    INFLUX_SENSOR_INVERTER_POWER_1=MY_SENEC:mpp1_power

Both halves used to disagree. The sensors read from the name in the table
(`SENEC`) while the collector wrote into `MY_SENEC`, so the dashboard stayed
empty, and a saved sensor kept a copy of the name that stayed behind when the
name changed.

`spec/services/export/sensor_mapping_contract_spec.rb` holds the two halves
together for every scenario. This one is the case that makes that check bite,
because every other scenario keeps the default name.
