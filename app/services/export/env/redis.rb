module Export
  class Env
    class Redis < Section
      def call
        env.add_section('Redis cache')
        volume_path_entry(Services::Redis, 'Redis data')
      end
    end
  end
end
