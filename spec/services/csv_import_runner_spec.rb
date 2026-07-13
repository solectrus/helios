RSpec.describe CsvImportRunner do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:open3_calls) { [] }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(File.join(data_path, 'helios'))
    File.write(File.join(data_path, '.env'),
               "INFLUX_ORG=acme\nINFLUX_BUCKET=solectrus\nINFLUX_TOKEN_WRITE=write-token\nTZ=Europe/Berlin\n")
    File.write(File.join(data_path, 'helios', 'config.yaml'), "system:\n  timezone: Europe/Berlin\n")

    allow(Orchestration::Runner).to receive(:host_data_path).and_return(host_data_path)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
    allow(described_class).to receive_messages(running?: false, preparing?: false, completing?: false)
    # Run the threaded prep work synchronously in tests so `docker run` happens
    # before assertions instead of on a background thread.
    allow(described_class).to receive(:spawn_preparing_thread!) do |instance|
      instance.send(:run_preparing!)
    end
    # Same for the completion thread (flushing + summaries-reset phases):
    # run synchronously so assertions see the side effects.
    allow(described_class).to receive(:spawn_completion_thread!) do |raw|
      described_class.new.process_completion!(raw)
    end
    allow(Configuration).to receive(:current).and_return(
      instance_double(Configuration, collectors_only?: false),
    )

    influx_container = instance_double(
      Orchestration::Container,
      name: 'solectrus-influxdb-1',
      service_name: 'influxdb',
      running?: true,
      json: { 'NetworkSettings' => { 'Networks' => { 'solectrus_default' => {} } } },
    )
    postgres_container = instance_double(Orchestration::Container, running?: true)
    allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(influx_container)
    allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(postgres_container)
    allow(Orchestration::DockerCli).to receive(:inspect_container)
      .with(described_class::CONTAINER_NAME).and_return(nil)

    FileUtils.mkdir_p(File.join(CsvImportUploader.extract_directory, '2024'))
    File.write(File.join(CsvImportUploader.extract_directory, '2024/week-01.csv'), 'a,b')

    allow(Open3).to receive(:capture2e) do |*args|
      open3_calls << args
      ['', instance_double(Process::Status, success?: true)]
    end
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.start' do
    it 'launches docker run with the expected mounts, network and influx env' do
      described_class.start

      cmd = open3_calls.find { |args| args.first == 'docker' && args[1] == 'run' }
      aggregate_failures do
        expect(cmd).not_to be_nil
        expect(cmd).to include('--name', 'helios-csv-import-runner')
        expect(cmd).to include('--network', 'solectrus_default')
        expect(cmd).to include('--mount',
                               "type=bind,source=#{host_data_path}/helios/csv-imports/extracted,target=/data,readonly")
        expect(cmd).to include('-e', 'INFLUX_HOST=influxdb')
        expect(cmd).to include('-e', 'INFLUX_TOKEN_WRITE=write-token')
        expect(cmd).to include('-e', 'INFLUX_ORG=acme')
        expect(cmd).to include('-e', 'INFLUX_BUCKET=solectrus')
        expect(cmd).to include(described_class::IMAGE)
      end
    end

    it 'passes through configured INFLUX_SENSOR_* mappings' do
      File.write(File.join(data_path, '.env'),
                 "INFLUX_ORG=acme\nINFLUX_BUCKET=s\nINFLUX_TOKEN_WRITE=w\n" \
                 "INFLUX_SENSOR_INVERTER_POWER=MYSENEC:inverter_power\n")

      described_class.start

      cmd = open3_calls.find { |args| args.first == 'docker' && args[1] == 'run' }
      expect(cmd).to include('-e', 'INFLUX_SENSOR_INVERTER_POWER=MYSENEC:inverter_power')
    end

    # The importer defaults every unset mapping to SENEC:*, so a name it does
    # not recognize is not an error — it silently imports to the wrong
    # measurement. These are the names it reads (csv-importer/app/config.rb).
    it 'passes through the battery mappings under the names the importer reads' do
      File.write(File.join(data_path, '.env'),
                 "INFLUX_ORG=acme\nINFLUX_BUCKET=s\nINFLUX_TOKEN_WRITE=w\n" \
                 "INFLUX_SENSOR_BATTERY_CHARGING_POWER=MYSENEC:bat_power_plus\n" \
                 "INFLUX_SENSOR_BATTERY_DISCHARGING_POWER=MYSENEC:bat_power_minus\n" \
                 "INFLUX_SENSOR_BATTERY_SOC=MYSENEC:bat_fuel_charge\n")

      described_class.start

      cmd = open3_calls.find { |args| args.first == 'docker' && args[1] == 'run' }
      aggregate_failures do
        expect(cmd).to include('-e', 'INFLUX_SENSOR_BATTERY_CHARGING_POWER=MYSENEC:bat_power_plus')
        expect(cmd).to include('-e', 'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER=MYSENEC:bat_power_minus')
        expect(cmd).to include('-e', 'INFLUX_SENSOR_BATTERY_SOC=MYSENEC:bat_fuel_charge')
      end
    end

    it 'passes SENEC_IGNORE when set in .env' do
      File.write(File.join(data_path, '.env'),
                 "INFLUX_ORG=a\nINFLUX_BUCKET=b\nINFLUX_TOKEN_WRITE=t\nSENEC_IGNORE=case_temp\n")

      described_class.start

      cmd = open3_calls.find { |args| args.first == 'docker' && args[1] == 'run' }
      expect(cmd).to include('-e', 'SENEC_IGNORE=case_temp')
    end

    it 'omits --network and uses the external host in collectors_only mode' do
      allow(Configuration.current).to receive(:collectors_only?).and_return(true)
      File.write(File.join(data_path, '.env'),
                 "INFLUX_ORG=a\nINFLUX_BUCKET=b\nINFLUX_TOKEN_WRITE=t\nINFLUX_HOST=influx.example.org\n")

      described_class.start

      cmd = open3_calls.find { |args| args.first == 'docker' && args[1] == 'run' }
      expect(cmd).not_to include('--network')
      expect(cmd).to include('-e', 'INFLUX_HOST=influx.example.org')
      expect(cmd).to include('-e', 'INFLUX_SCHEMA=https')
    end

    it 'refuses to start while a backup is in progress (covers the S3 phases too)' do
      allow(BackupRunner).to receive(:in_progress).and_return(double)

      expect { described_class.start }
        .to raise_error(described_class::Error, I18n.t('csv_imports.runner.errors.backup_in_progress'))
    end

    it 'refuses to start while a restore is in progress (covers the S3 download phase)' do
      allow(RestoreRunner).to receive(:in_progress).and_return(double)

      expect { described_class.start }
        .to raise_error(described_class::Error, I18n.t('csv_imports.runner.errors.restore_in_progress'))
    end

    it 'refuses to start when no CSVs are extracted' do
      FileUtils.rm_rf(CsvImportUploader.extract_directory)

      expect { described_class.start }
        .to raise_error(described_class::Error, I18n.t('csv_imports.runner.unavailable.no_csv_files'))
    end

    it 'refuses to start when InfluxDB is not running' do
      stopped_influx = instance_double(Orchestration::Container, running?: false)
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(stopped_influx)

      expect { described_class.start }
        .to raise_error(described_class::Error,
                        I18n.t('csv_imports.runner.unavailable.influxdb_not_running'))
    end

    it 'refuses to start when PostgreSQL is not running' do
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(nil)

      expect { described_class.start }
        .to raise_error(described_class::Error,
                        I18n.t('csv_imports.runner.unavailable.postgresql_not_running'))
    end

    it 'raises a clean Error when the .env file is missing' do
      File.delete(File.join(data_path, '.env'))

      expect { described_class.start }
        .to raise_error(described_class::Error,
                        I18n.t('csv_imports.runner.unavailable.env_missing'))
    end

    it 'refuses to start without an INFLUX_TOKEN_WRITE' do
      File.write(File.join(data_path, '.env'), "INFLUX_ORG=a\nINFLUX_BUCKET=b\n")

      expect { described_class.start }
        .to raise_error(described_class::Error,
                        I18n.t('csv_imports.runner.unavailable.influx_target_missing'))
    end
  end

  describe '.detect_completion!' do
    it 'is a no-op when no container exists' do
      allow(Orchestration::DockerCli).to receive(:inspect_container)
        .with(described_class::CONTAINER_NAME).and_return(nil)

      expect { described_class.detect_completion! }.not_to raise_error
    end

    it 'is a no-op while the container is still running' do
      allow(Orchestration::DockerCli).to receive(:inspect_container)
        .with(described_class::CONTAINER_NAME)
        .and_return('State' => { 'Running' => true })
      allow(described_class).to receive(:spawn_completion_thread!)

      described_class.detect_completion!

      expect(described_class).not_to have_received(:spawn_completion_thread!)
    end

    it 'spawns the completion thread for an exited container' do
      raw = { 'State' => { 'Running' => false, 'Status' => 'exited', 'ExitCode' => 0 } }
      allow(Orchestration::DockerCli).to receive(:inspect_container)
        .with(described_class::CONTAINER_NAME).and_return(raw)
      allow(described_class).to receive(:spawn_completion_thread!)

      described_class.detect_completion!

      expect(described_class).to have_received(:spawn_completion_thread!).with(raw)
    end
  end

  describe '#process_completion!' do
    let(:redis_container) { instance_double(Orchestration::Container, running?: true) }
    let(:postgres_container) do
      instance_double(Orchestration::Container, running?: true, name: 'solectrus-postgresql-1')
    end

    before do
      allow(Orchestration::Container).to receive(:find).with('redis').and_return(redis_container)
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(postgres_container)
      allow(Orchestration::RedisCacheFlush).to receive(:call).with(redis_container).and_return(true)
      allow(Configuration.current).to receive(:postgresql).and_return(double(password: 'pg-pass'))
      FileUtils.mkdir_p(File.join(data_path, 'helios', 'csv-imports', 'extracted'))
      File.write(File.join(data_path, 'helios', 'csv-imports', 'upload.zip'), 'zip')

      allow(Open3).to receive(:capture2e).with('docker', 'logs', '--tail', '500', described_class::CONTAINER_NAME)
                                         .and_return(["Imported 12 files\n",
                                                      instance_double(Process::Status, success?: true)])
    end

    it 'runs the flushing and summaries-reset phases on success, then cleans up' do
      described_class.new.process_completion!(
        'State' => { 'Status' => 'exited', 'ExitCode' => 0 },
      )

      expect(Orchestration::RedisCacheFlush).to have_received(:call).with(redis_container)
      truncate_call = open3_calls.find { |args| args.include?('TRUNCATE TABLE summaries CASCADE') }
      aggregate_failures do
        expect(truncate_call).to include('docker', 'exec', '-e', 'PGPASSWORD=pg-pass', 'solectrus-postgresql-1')
        expect(truncate_call).to include('psql', '-U', 'postgres', '-d', 'solectrus_production')
      end
      expect(File).not_to exist(File.join(data_path, 'helios', 'csv-imports', 'upload.zip'))
      expect(File).not_to exist(File.join(data_path, 'helios', 'csv-imports', 'extracted'))
    end

    it 'scopes the summaries reset to days inferred from SENEC weekly filenames' do
      FileUtils.rm_rf(CsvImportUploader.extract_directory)
      FileUtils.mkdir_p(CsvImportUploader.extract_directory)
      File.write(File.join(CsvImportUploader.extract_directory, 'S123-week-22-2026.csv'), 'a,b')

      described_class.new.process_completion!(
        'State' => { 'Status' => 'exited', 'ExitCode' => 0 },
      )

      delete_call = open3_calls.find { |args| args.any? { |a| a.to_s.start_with?('DELETE FROM summaries') } }
      sql = delete_call.last
      expect(sql).to eq(
        "DELETE FROM summaries WHERE date BETWEEN '2026-05-25' AND '2026-05-31'",
      )
      expect(open3_calls).not_to include(array_including('TRUNCATE TABLE summaries CASCADE'))
    end

    it 'persists the imported file count parsed from the importer log on success' do
      described_class.new.process_completion!(
        'State' => { 'Status' => 'exited', 'ExitCode' => 0 },
      )

      expect(described_class.success_message).to eq('12')
    end

    it 'falls back to failure when the importer exited 0 but no file count was parsed' do
      allow(Open3).to receive(:capture2e).with('docker', 'logs', '--tail', '500', described_class::CONTAINER_NAME)
                                         .and_return(['no summary line here',
                                                      instance_double(Process::Status, success?: true)])

      described_class.new.process_completion!(
        'State' => { 'Status' => 'exited', 'ExitCode' => 0 },
      )

      expect(described_class.success_message).to be_nil
      expect(described_class.error_message).to be_present
    end

    it 'rejects a created/dead container even with ExitCode 0' do
      described_class.new.process_completion!(
        'State' => { 'Status' => 'created', 'ExitCode' => 0 },
      )

      expect(Orchestration::RedisCacheFlush).not_to have_received(:call)
      expect(open3_calls).not_to include(array_including('TRUNCATE TABLE summaries CASCADE'))
    end

    it 'surfaces partial-phase failure with a multi-line error message' do
      allow(Orchestration::RedisCacheFlush).to receive(:call).with(redis_container).and_return(false)

      described_class.new.process_completion!(
        'State' => { 'Status' => 'exited', 'ExitCode' => 0 },
      )

      expect(described_class.success_message).to be_nil
      expect(described_class.error_message).to include(
        I18n.t('csv_imports.runner.errors.phases_failed_header'),
        I18n.t('csv_imports.runner.errors.redis_flush_failed'),
      )
    end

    it 'writes an error file on non-zero exit and skips remaining phases' do
      raw = { 'State' => { 'Status' => 'exited', 'ExitCode' => 1, 'Error' => 'image pull failed' } }
      described_class.new.process_completion!(raw)

      expect(Orchestration::RedisCacheFlush).not_to have_received(:call)
      expect(open3_calls).not_to include(array_including('TRUNCATE TABLE summaries CASCADE'))
      expect(open3_calls).not_to include(array_including(a_string_starting_with('DELETE FROM summaries')))
      expect(described_class.error_message).to include('image pull failed')
    end
  end
end
