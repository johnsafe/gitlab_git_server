# config sidekiq client
local_sidekiq_redis = Gitlab::Git::Settings.redis.local_sidekiq_redis
url = if local_sidekiq_redis['password'].nil?
        "redis://#{local_sidekiq_redis['host']}:#{local_sidekiq_redis['port']}/#{local_sidekiq_redis['db']}"
      else
        "redis://:#{local_sidekiq_redis['password']}@#{local_sidekiq_redis['host']}:#{local_sidekiq_redis['port']}/#{local_sidekiq_redis['db']}"
      end

Sidekiq.configure_client do |config|
  config.redis = { url: url,
                   namespace: Gitlab::Git::Settings.gitlab_git_server_sidekiq.namespace+":"+Gitlab::Git::Settings.hostname }
end

Sidekiq.configure_server do |config|
  config.redis = {
      url: url,
      namespace: Gitlab::Git::Settings.gitlab_git_server_sidekiq.namespace+":"+Gitlab::Git::Settings.hostname
  }
end
