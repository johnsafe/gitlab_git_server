module Gitlab
  module Git
    module Workers
      class ForkWorker
        TEMP_SVN_PATH = Settings.temp_svn_path
        include Gitlab::Git::Popen
        include Sidekiq::Worker
        include Gitlab::Git::RedisHelper

        def perform(path, url, type, is_fork = false)
          user_name, repo_name = path.split('/')
          pre_path = Settings.repository.pre_path
          owner_path = File.join(pre_path, user_name)
          popen(["mkdir  #{user_name}"], pre_path)  unless File.exist?(owner_path)


          cmd = "git clone #{is_fork ? '--bare' : '--mirror'} #{url} #{owner_path}/#{repo_name}"

          Open3.popen3(cmd) do |i,o,e,w|
            p "process id : " + w.pid.to_s
            begin
              Timeout.timeout(Settings.git_fork_timeout) do
                if o.eof?
                  Gitlab::Git::Repository.add_hooks(path)
                  Sidekiq.logger.info("******************#{is_fork ? '派生' : '导入'}项目 #{url}到#{owner_path}完成**********************")
                end
              end
            rescue Timeout::Error
              Sidekiq.logger.info("******************#{is_fork ? '派生' : '导入'}项目超时，进程#{w.pid}自动结束**** #{cmd}**********************")
              Process.kill('INT', w.pid)
            end
            front_cache_redis.hdel('backend_doing_queue', path)
          end

=begin
          output, status = popen(["git clone #{is_fork ? '--bare' : '--mirror'} #{url} #{repo_name}"], owner_path)
          Gitlab::Git::Repository.add_hooks(path) if status
          front_cache_redis.hdel('backend_doing_queue', path)
          #repo sync msg
          if status
            if is_fork
              tmp_arr = url.split('/')
              pathname = tmp_arr[tmp_arr.size - 2, 2].join('/')
              # ProjectSyncClient.push path, 'fork', pathname
            else
              # ProjectSyncClient.push path, 'create'
            end
          end
          return output, status
=end
        end

        private

        def add_and_push_to_server(path)
          Gitlab::Git::Repository.init(path)
          temp_project_path = File.join(TEMP_SVN_PATH, path)
          repo_path = File.join(Settings.repository.pre_path, path)
        
          popen(["cp -Rf .git/refs/remotes/tags/* .git/refs/tags/ && rm -Rf .git/refs/remotes/tags"], temp_project_path)
          popen(["cp -Rf .git/refs/remotes/* .git/refs/heads/ && rm -Rf .git/refs/remotes"], temp_project_path)
          popen(["git remote add origin #{repo_path} && git push --all && git push --tags"], temp_project_path)
        
          popen(["rm -fr #{path}"], TEMP_SVN_PATH)
        end
        
        def clone_to_temp(user_name, repo_name, url)
          owner_path = File.join(TEMP_SVN_PATH, user_name)
          popen(["mkdir  #{user_name}"], TEMP_SVN_PATH)  unless File.exist?(owner_path)

          popen(["rm -fr  #{repo_name}"], owner_path)
          output, status = popen(["git svn clone #{url} #{repo_name}"], owner_path)
        end
      end
    end
  end
end
         
         
         
