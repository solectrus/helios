class CsvImportRunner
  # Parses the csv-importer's stdout to drive the progress and success UI.
  #
  # IMPORTANT: This couples HELIOS to the importer's log format. Since
  # csv-importer 0dd4738 (AppLogger emits bare `msg\n` without timestamp
  # or severity prefix), each successful file produces one log line:
  #
  #   Imported /data/<path> (<Adapter>, <N> rows)
  #
  # The patterns below match these literal substrings printed by
  # csv-importer (see https://github.com/solectrus/csv-importer/blob/main/app/import.rb):
  #
  #   - `Imported <path> (<Adapter>, <N> rows)` (per file with count > 0)
  #     → DONE_PATTERN; counted to derive "N files done" while running.
  #       The trailing `, <N> rows)` is what disambiguates it from the
  #       final summary line below. Older importer versions wrote
  #       `points` instead of `rows`, so both nouns are accepted.
  #
  #   - `Imported <N> files` (the run's final summary, on its own line)
  #     → TOTAL_PATTERN captures the total for the success card
  #
  # If the importer changes any of these strings, the live progress /
  # success counter silently degrades to "0 / no count" — functionally
  # harmless, but the user loses the feedback. A canary spec under
  # spec/services/csv_import_runner/log_parser_spec.rb pins the patterns;
  # bump the importer image with care and re-run that spec when updating.
  module LogParser
    DONE_PATTERN = /Imported .+ \(.+, \d+ (?:rows|points)\)/
    TOTAL_PATTERN = /Imported (?<count>\d+) files?\b/

    module_function

    # Live snapshot for the progress UI. Returns `{ done: Integer }`.
    def progress(log)
      { done: log.scan(DONE_PATTERN).size }
    end

    # Total file count from the final summary line. Returns 0 when the
    # log does not contain a summary (interrupted run, unexpected log
    # format).
    def total_files(log)
      log[TOTAL_PATTERN, :count].to_i
    end
  end
end
