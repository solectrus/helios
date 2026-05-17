module Services
  class CachesController < BaseController
    before_action :require_redis

    # DELETE /services/:service_id/cache - Flush the Redis cache
    def destroy
      if Orchestration::RedisCacheFlush.call(container)
        redirect_to services_path, notice: t('.success')
      else
        redirect_to services_path, alert: t('.failure')
      end
    end

    private

    # The cache flush is Redis-specific; no other service exposes it.
    def require_redis
      head :not_found unless service_name == 'redis'
    end
  end
end
