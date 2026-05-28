class CsvImportsController < ApplicationController
  before_action :advance_state

  def show
    load_state
  end

  def create
    CsvImportRunner.precheck!
    CsvImportUploader.start(params[:file])
    start_runner_or_cleanup!
    redirect_to csv_imports_path
  rescue CsvImportUploader::Error, CsvImportRunner::Error => e
    @upload_error = e.message
    load_state
    render :show, status: :unprocessable_content
  end

  # Dismiss a finished error or success: clears state and sends the user
  # back to /datasources (the entry point the CSV import was reached
  # from). Refuses while an import is in flight — cleanup! would remove
  # the extract_directory bind-mounted into the live container.
  def destroy
    if CsvImportRunner.in_progress?
      redirect_to csv_imports_path
      return
    end

    CsvImportRunner.clear_error!
    CsvImportRunner.clear_success!
    CsvImportUploader.cleanup!
    redirect_to datasources_path
  end

  private

  # validate! can raise after the upload has already extracted to disk
  # (e.g. a backup/restore claimed the lock during the upload window). In
  # that case wipe the orphaned upload.zip + extract/ so we don't leak up
  # to 1 GB until the next upload or destroy. Skip the cleanup if another
  # CSV import just claimed the lock — they now own the shared paths.
  def start_runner_or_cleanup!
    CsvImportRunner.start
  rescue CsvImportRunner::Error
    CsvImportUploader.cleanup! unless CsvImportRunner.in_progress?
    raise
  end

  # Single source of truth for "did the previous run just finish?".
  # Runs before show *and* before create so a stale exited container
  # is reaped before validation runs (which would otherwise block on
  # the lingering container name).
  def advance_state
    CsvImportRunner.detect_completion!
  end

  def load_state
    @running = CsvImportRunner.in_progress?
    @error_message = CsvImportRunner.error_message
    @success_count = success_count
    @progress = @running ? CsvImportRunner.progress : nil
    @unavailable_reason =
      if @running || @error_message || @success_count
        nil
      else
        CsvImportRunner.unavailable_reason
      end
  end

  # Treat 0 (parsed from a missing summary line) the same as nil — both
  # mean "no successful file count to display"; rendering a card claiming
  # "0 CSV files were imported" hides whatever actually happened.
  def success_count
    raw = CsvImportRunner.success_message
    return nil if raw.blank?

    count = raw.to_i
    count.positive? ? count : nil
  end
end
