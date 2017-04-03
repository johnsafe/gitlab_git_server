module Gitlab
  module Git
     class CacheHost
        HOST_NAME = Gitlab::Git::Settings.hostname
        HOST_CACHE_DEFAULT_TIME = Gitlab::Git::Settings.drb.timeout
        extend Gitlab::Git::RedisHelper

        class << self
          def set_cache_host(repo_path)
             key = "drb_catch_server:#{repo_path}"
             route_redis.set(key, HOST_NAME)
             route_redis.expireat key, (Time.now + HOST_CACHE_DEFAULT_TIME).to_i
          end
 
          def delete_cache_host(repo_path)
             route_redis.del("drb_catch_server:#{repo_path}")
          end
       end
     end
  end
end
