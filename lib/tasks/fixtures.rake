namespace :fixtures do
  # Recursively sort hash keys alphabetically.
  def deep_sort_keys(obj)
    case obj
    when Hash then obj.sort.to_h.transform_values { |v| deep_sort_keys(v) }
    when Array then obj.map { |e| deep_sort_keys(e) }
    else obj
    end
  end

  def regenerate_scenario(scenario_path)
    Current.configuration = nil
    [Configuration.path, Compose.path, Env.path].each { |p| FileUtils.rm_f(p) }

    config = import_scenario(scenario_path)
    dump_expected_fixtures(config, scenario_path)
  end

  def import_scenario(scenario_path)
    stack_reader = Import::StackReader.new(
      compose_path: scenario_path.join('old_compose.yaml'),
      env_path: scenario_path.join('old.env'),
    )
    Import::ConfigurationImporter.new(stack_reader).import!
  end

  def dump_expected_fixtures(config, scenario_path)
    # Preserve root-level key order (grouped logically by the importer) but
    # sort nested keys so diffs stay stable across importer reshuffles.
    data = YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
    sorted = data.transform_values { |v| deep_sort_keys(v) }
    File.write(scenario_path.join('expected_config.yaml'), YAML.dump(sorted))

    Export::Builder.new(config).write!
    FileUtils.cp(Compose.path, scenario_path.join('expected_compose.yaml'))
    FileUtils.cp(Env.path, scenario_path.join('expected.env'))
  end

  desc 'Regenerate expected_config.yaml + expected_compose.yaml + expected.env for every import scenario'
  task regenerate: :environment do
    # Export output depends on Rails.env (e.g. Helios service is exported in
    # test but skipped in development), so generate fixtures in the same env
    # that scenarios_spec.rb runs in.
    abort 'Run with RAILS_ENV=test so fixtures match test-env exports.' unless Rails.env.test?

    require 'fileutils'
    require 'tmpdir'

    scenarios_dir = Rails.root.join('spec/fixtures/import_scenarios')
    scenarios = Pathname
                .glob(scenarios_dir.join('*/expected_config.yaml'))
                .map { |p| p.dirname.basename.to_s }
                .sort

    Dir.mktmpdir do |tmp|
      Rails.configuration.data_path = tmp
      FileUtils.mkdir_p(File.dirname(Configuration.path))

      scenarios.each do |name|
        regenerate_scenario(scenarios_dir.join(name))
        puts "Regenerated #{name}/ (expected_config.yaml, expected_compose.yaml, expected.env)"
      end
    end
  end
end
