# GitLab Git Server
A server for gitlab_git

##install
1. install  ruby 2.1.2p95
2. git clone git@code.csdn.net:huawei_code/gitlab_git_server.git
3. cd gitlab_git_server
4. bundle install --path .bundle
5. mkdir logs
5. mkdir pids


##run
bundle exec gitlab-git-server

##production run with god
1. Install god  `gem install god`
2. Config god and start services `god -c /full/path/to/gitlab_git_server/config.god`
3. Stop services   `god stop gitlab-git-servers`
3. Start services  `god start gitlab-git-servers`
4. Servers status  `god status`

god --help for more infor


##test
bundle exec rspec
