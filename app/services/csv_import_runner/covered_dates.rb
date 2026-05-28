class CsvImportRunner
  # Scans CSV filenames in the extract directory and returns the union
  # of dates the upload covers, or nil if at least one filename's date
  # range cannot be determined unambiguously. CsvImportRunner uses this
  # to scope the post-import summaries reset to the imported days
  # instead of wiping the whole table.
  #
  # Recognized patterns:
  #   SENEC      `…week-WW-YYYY.csv`           → 7 days (Mon..Sun, ISO week)
  #   Sungrow    `Tagesbericht_YYYYMMDD.csv`   → 1 day
  #   SolarEdge  no consistent date in name    → unrecognized; caller
  #                                              must fall back to a
  #                                              full table truncate.
  module CoveredDates
    SENEC = /(?:\A|[-_])week[-_](?<week>\d{1,2})[-_](?<year>\d{4})\.csv\z/i
    SUNGROW = /(?:\A|[-_])tagesbericht[-_](?<year>\d{4})(?<month>\d{2})(?<day>\d{2})\.csv\z/i

    module_function

    # Returns a sorted Array<Date> or nil. `nil` means "give up and
    # truncate everything"; an empty input directory also returns nil
    # for the same reason — no info, can't scope.
    def scan(root)
      paths = Dir.glob(::File.join(root, '**', '*.csv'), ::File::FNM_CASEFOLD)
      return nil if paths.empty?

      paths.each_with_object(Set.new) do |path, acc|
        dates = dates_for(::File.basename(path)) || (return nil)
        acc.merge(dates)
      end.sort
    end

    def dates_for(basename)
      if (m = basename.match(SENEC))
        senec_week_dates(m[:year].to_i, m[:week].to_i)
      elsif (m = basename.match(SUNGROW))
        [Date.new(m[:year].to_i, m[:month].to_i, m[:day].to_i)]
      end
    rescue Date::Error
      nil
    end

    def senec_week_dates(year, week)
      monday = Date.commercial(year, week, 1)
      (monday..(monday + 6)).to_a
    end
  end
end
