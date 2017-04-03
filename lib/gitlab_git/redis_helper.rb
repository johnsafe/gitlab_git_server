module Gitlab
  module Git
    module RedisHelper
      def route_redis
        $route_redis ||= Redis::Store.new(:host => Gitlab::Git::Settings.redis.route_redis.host, 
                                          :port => Gitlab::Git::Settings.redis.route_redis.port, 
                                          :db   => Gitlab::Git::Settings.redis.route_redis.db,
                                          :password    => Gitlab::Git::Settings.redis.route_redis.password)
      end
     

      def front_cache_redis
        $front_cache_redis ||= Redis::Store.new(:host => Gitlab::Git::Settings.redis.front_cache_redis.host, 
                                                :port => Gitlab::Git::Settings.redis.front_cache_redis.port, 
                                                :db   => Gitlab::Git::Settings.redis.front_cache_redis.db,
                                                :password   => Gitlab::Git::Settings.redis.front_cache_redis.password)
      end

      def local_cache_redis
        $local_cache_redis ||= Redis::Store.new(:host => Gitlab::Git::Settings.redis.local_cache_redis.host, 
                                                :port => Gitlab::Git::Settings.redis.local_cache_redis.port, 
                                                :db   => Gitlab::Git::Settings.redis.local_cache_redis.db,
                                                :password   => Gitlab::Git::Settings.redis.local_cache_redis.password)
      end
    end
  end
end
