class Current < ActiveSupport::CurrentAttributes
  attribute :preferences, :configuration

  resets { @request_cache = nil }

  # Memoizes the result of the block under `key` for the lifetime of the
  # current request (or background-job executor block). Avoids re-running
  # expensive lookups — like docker-inspect probes for the backup/restore
  # runners — on multiple call sites within the same request.
  def fetch(key)
    @request_cache ||= {}
    return @request_cache[key] if @request_cache.key?(key)

    @request_cache[key] = yield
  end
end
