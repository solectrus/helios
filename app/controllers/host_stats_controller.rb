class HostStatsController < ApplicationController
  def show
    @snapshot = HostStats.snapshot
    fresh_when etag: @snapshot, template: false
  end
end
