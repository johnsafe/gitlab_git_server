Gem::Specification.new do |s|
  s.name        = 'gitlab_git_server'
  s.version     = `cat VERSION`
  s.date        = Time.now.strftime("%Y-%m-%d")
  s.summary     = "Gitlab::Git library"
  s.description = "a server for gitlab_git by csdn"
  s.authors     = ["Liuhq", "yanlp"]
  s.email       = 'codesupport@csdn.net'
  s.license     = 'MIT'
  s.files       = `git ls-files lib/`.split("\n") << 'VERSION'
  s.homepage    = 'http://rubygems.org/gems/gitlab_git'

  s.executables = ["gitlab-git-server", "sidekiq-server"]
  s.bindir = "bin"
  s.require_path = "lib"
    
  s.add_dependency("rchardet19", "~> 1.3")
  s.add_dependency("redis", "~> 3.2")
  s.add_dependency("redis-store", "~> 1.1.4")
  s.add_dependency("redis-namespace", "1.5.2")
  s.add_dependency("pygments.rb", "~> 0.6.3")
  s.add_dependency("github-markup", "~> 0.7.4")
  s.add_dependency("github-markdown", "~> 0.5.5")
  s.add_dependency('nokogiri', '~> 1.6.6.2')
  s.add_dependency('sidekiq', '~> 3.2.1')
  s.add_dependency('settingslogic')
end
