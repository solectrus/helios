class CsvImportRunner
  # Persists the runner's last-run outcome (success log or error message)
  # as plain files in the shared runtime directory. The files outlive the
  # container itself, so the UI can show the previous run's result after
  # the user comes back to the page.
  #
  # File-based instead of Rails.cache because the data must survive HELIOS
  # restarts (e.g. a Watchtower self-update mid-render) and stays trivially
  # observable for support bundles.
  module State
    ERROR_FILENAME = 'csv-import-error.txt'.freeze
    SUCCESS_FILENAME = 'csv-import-success.txt'.freeze

    module_function

    def error_message
      read(error_file_path)
    end

    def success_message
      read(success_file_path)
    end

    def write_error!(message)
      write(error_file_path, message)
    end

    def write_success!(message)
      write(success_file_path, message)
    end

    def clear_error!
      FileUtils.rm_f(error_file_path)
    end

    def clear_success!
      FileUtils.rm_f(success_file_path)
    end

    def clear_all!
      clear_error!
      clear_success!
    end

    def error_file_path
      ::File.join(DetachedRunner.runtime_directory, ERROR_FILENAME)
    end

    def success_file_path
      ::File.join(DetachedRunner.runtime_directory, SUCCESS_FILENAME)
    end

    def read(path)
      ::File.read(path).strip.presence
    rescue Errno::ENOENT
      nil
    end

    def write(path, content)
      FileUtils.mkdir_p(::File.dirname(path))
      ::File.write(path, content)
    end
  end
end
