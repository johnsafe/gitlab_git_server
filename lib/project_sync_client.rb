#encoding: utf-8
require 'singleton'
#后端仓库同步Sidekiq Client
#使用：
#client = ProjectSyncClient.instance
#client.push 'test2/test_project', 'push'
class ProjectSyncClient
  include Singleton

  STATUS_WAIT_SYNC = 1 #等待同步
  STATUS_SYNCING = 2 #正在同步中
  STATUS_SYNC_FINISH = 3 #同步完成

  #router_redis_config 项目redis路由redis配置，{'host'=> '127.0.0.1', 'port'=> 6379, 'db'=> 0}
  #worker_redis_config 项目同步队列redis配置，{'host'=> '127.0.0.1', 'port'=> 6379, 'db'=> 0, 'namespace' => 'prj_sync'}
  def initialize
    @router_redis = Redis.new url: "redis://#{Gitlab::Git::Settings.redis.route_redis.host}:#{Gitlab::Git::Settings.redis.route_redis.port}/#{Gitlab::Git::Settings.redis.route_redis.db}",
                              password: Gitlab::Git::Settings.redis.route_redis.password
    worker_redis_url = "redis://#{Gitlab::Git::Settings.redis.sync_worker_redis.host}:#{Gitlab::Git::Settings.redis.sync_worker_redis.port}/#{Gitlab::Git::Settings.redis.sync_worker_redis.db}"
    @worker_redis = Redis.new url: worker_redis_url, password: Gitlab::Git::Settings.redis.sync_worker_redis.password
    redis = Redis::Namespace.new(Gitlab::Git::Settings.redis.sync_worker_redis.namespace, redis: @worker_redis)
    @sidekiq_client = Sidekiq::Client.new ConnectionPool.new { redis }
  end

  #读取项目redis路由信息
  def get_repo_router(pathname)
    @router_redis.hgetall "repo:#{pathname}.git"
  end

  #推送同步消息
  #pathname项目pathname fxhover/project1
  #action操作
  #other_info其他信息
  #be后端server id，为nil则推送消息到所有从机器worker队列
  def push(pathname, action, other_info = nil, be = nil)
    begin
      pathname = pathname.chomp '.git' #如果path以.git结尾的去掉.git
      other_info = other_info.chomp '.git' if other_info
      router = get_repo_router pathname
      raise "repo:#{pathname} router not found in redis." if router.empty?
      raise "action:#{action} error." unless ['create', 'fork', 'rename', 'delete', 'push'].include? action
      update_timestamp = Time.now.to_i
      logger.info "push sync msg args: pathname: #{pathname}, action: #{action}, other: #{other_info}, be: #{be}, router: #{router.inspect}"

      #修改项目的redis状态，主服务器更新时间，从服务器将状态设置成待同步
      status_data = [{host: router['m'], status: STATUS_SYNC_FINISH, timestamp: update_timestamp}]
      #从服务器
      slaves = be ? [be] : router['s'].split(',')
      slaves.each do |slave|
        status_data.push host: slave, status: STATUS_WAIT_SYNC, timestamp: nil
      end
      batch_update_repo_status pathname, status_data

      #队列参数
      args = {prj: pathname, act: action, t: update_timestamp}
      args[:o] = other_info if other_info
      #获取任务编号
      task_no = get_queue_task_no
      slaves.each do |slave|
        #推送消息
        @sidekiq_client.push 'queue' => slave, 'class' => 'ProjectSyncWorker', 'args' => [args, task_no]
      end
    rescue => e
      logger.info "push msg error: ErrorClass: #{e.class}, Message: #{e.message}, pathname: #{pathname}, action: #{action}, other: #{other_info}, be: #{be}, router: #{router.inspect}, backtrace: \n#{e.backtrace.join("\n")}"
    end
  end

  #修改一个项目多个后端机的redis状态信息
  #pathname 项目pathname
  #data 状态数据，array格式：[{host: 'be1', status: 1, timestamp: 1420190290}, {host: 'be2', status: 3, timestamp: 1420103232}]
  def batch_update_repo_status(pathname, data)
    router = get_repo_router pathname
    redis_data = {}
    data.each do |val|
      old_timestamp = router["status:#{val[:host]}"].split(',')[1]
      redis_data["status:#{val[:host]}"] = "#{val[:status]},#{val[:timestamp] ? val[:timestamp] : old_timestamp}"
    end
    redis_data = redis_data.flatten
    @router_redis.hmset "repo:#{pathname}.git", *redis_data unless redis_data.empty?
  end

  #修改一个项目单个后端机的redis状态信息
  def update_repo_status(pathname, lid, status, timestamp=nil)
    batch_update_repo_status pathname, [{host: lid, status: status, timestamp: timestamp}]
  end

  #获取队列的编号
  def get_queue_task_no
    key = "prj_sync:last_task_no"
    @worker_redis.incr key
  end

  def logger
    # gitlab_git_server is a submodle for code_be mv logs to code_be/logs
    @logger ||= Logger.new File.join(Dir.pwd,"logs", "sync_client.log")
  end

  def self.push(pathname, action, other_info = nil, be = nil)
    self.instance.push pathname, action, other_info, be
  end
end
