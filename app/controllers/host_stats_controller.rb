class HostStatsController < ApplicationController
  def show
    @snapshot = HostStats.snapshot
    fresh_when etag: @snapshot
  end
end
