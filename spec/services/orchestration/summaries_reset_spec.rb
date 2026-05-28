RSpec.describe Orchestration::SummariesReset do
  describe '#sql' do
    it 'truncates the whole table when no dates are supplied' do
      expect(build(dates: nil).send(:sql)).to eq('TRUNCATE TABLE summaries CASCADE')
    end

    it 'truncates the whole table when the dates list is empty' do
      expect(build(dates: []).send(:sql)).to eq('TRUNCATE TABLE summaries CASCADE')
    end

    it 'collapses a single SENEC week into one BETWEEN range' do
      week = (Date.new(2026, 5, 25)..Date.new(2026, 5, 31)).to_a

      expect(build(dates: week).send(:sql)).to eq(
        "DELETE FROM summaries WHERE date BETWEEN '2026-05-25' AND '2026-05-31'",
      )
    end

    it 'emits a degenerate BETWEEN x AND x for a single day' do
      expect(build(dates: [Date.new(2023, 6, 21)]).send(:sql)).to eq(
        "DELETE FROM summaries WHERE date BETWEEN '2023-06-21' AND '2023-06-21'",
      )
    end

    it 'splits non-contiguous dates into OR-joined BETWEEN clauses' do
      dates = (Date.new(2026, 5, 25)..Date.new(2026, 5, 31)).to_a +
              (Date.new(2026, 6, 8)..Date.new(2026, 6, 14)).to_a

      expect(build(dates: dates).send(:sql)).to eq(
        "DELETE FROM summaries WHERE date BETWEEN '2026-05-25' AND '2026-05-31' " \
        "OR date BETWEEN '2026-06-08' AND '2026-06-14'",
      )
    end

    it 'sorts and deduplicates regardless of input order' do
      dates = [Date.new(2024, 1, 2), Date.new(2024, 1, 1), Date.new(2024, 1, 2)]

      expect(build(dates: dates).send(:sql)).to eq(
        "DELETE FROM summaries WHERE date BETWEEN '2024-01-01' AND '2024-01-02'",
      )
    end
  end

  def build(dates:)
    described_class.new(dates: dates, container: instance_double(Orchestration::Container))
  end
end
