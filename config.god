#HOME = "/home/git/gitlab_git_server"
SERVER_HOME = "/home/git/code_be/gitlab_git_server"

God.pid_file_directory = File.join(SERVER_HOME, 'pids')
%w{9001}.each do |port|
  God.watch do |w|
    w.dir   = SERVER_HOME
    w.name  = "gitlab-git-server-#{port}"
    w.group = "gitlab-git-servers"
    w.start = "bundle exec gitlab-git-server -p #{port}"

    w.log   = File.join(SERVER_HOME, "logs", "god_#{port}.log")
    w.behavior(:clean_pid_file)
    w.keepalive(:memory_max => 150.gigabytes, :cpu_max => 50.percent)
  end
end
