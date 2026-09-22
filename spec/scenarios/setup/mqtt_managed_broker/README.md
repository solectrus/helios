# mqtt_managed_broker

An installation whose measurements all arrive over MQTT, and the only scenario in which HELIOS runs a broker of its own. Nothing is polled here: no device answers on the network, no cloud account is signed in. The devices publish, and the stack receives.

The broker is the reason for the scenario. `Export::Services::Mosquitto.adoptable?` is false, so no import can ever produce one, and the setup family is the only place the managed broker reaches a snapshot at all.

## What one answer switches on

The MQTT screen asks which kind of broker runs, and this scenario picks the internal one. That single answer reaches `config.yaml` as `mqtt.broker_managed: true` and produces four things in the stack.

1. The `mosquitto` service. Mosquitto 2.x listens on localhost alone until a configuration file names a listener, so the container writes its own configuration and its own password file at start, and then replaces itself with the broker.
2. A published host port. The scenario runs no reverse proxy, so the broker holds 1883 on the host itself. Behind a Traefik of HELIOS it publishes no port and carries routers instead, which `spec/services/export/services/mosquitto_spec.rb` covers.
3. The address the collector uses. `MQTT_HOST` becomes `mosquitto`, the service name inside the compose network, and the collector waits for `service_healthy` before it starts.
4. A login the user cannot switch off. The survey takes both halves as mandatory, and the generated configuration says `allow_anonymous false` whatever it finds.

## What the survey decides on its own

`broker_external` is a question the UI asks and nothing stores. It never appears in `config.yaml`, because the kind of broker follows from `mqtt.broker_managed`. The scenario answers it as `false` and the walk drops it.

The credentials travel too. Both belong to the MQTT screen, and both land under `mosquitto`, which is what `Configuration::BORROWED_FIELDS` decides. The user name is the default of the question, so the answers name the password alone.

## The sensor

One sensor reads from a topic, and every question about it keeps its default: the kind is `topic`, the extraction is `plain`, and the data type is `float`. The answers therefore hold the topic and nothing else, and the export writes `MAPPING_0_*` for the collector plus `INFLUX_SENSOR_INVERTER_POWER` for the dashboard.

A topic that feeds no sensor is a different path and stays out of here. `import/with_mqtt` carries four of them, JSON keys and formulas included.

## Read against raspi_senec_local

Neither scenario runs a reverse proxy or a backup, so the difference between them is the source alone. The other one picks SENEC for one sensor and gets sixteen, all of them filled by a collector that polls a device. This one gets exactly the sensor it names, and the data arrives only when a device decides to publish.
