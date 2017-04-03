source "http://rubygems.org"
gemspec

# gem 'gitlab_git', git: "http://rnd-isourceb.huawei.com/code/gitlab_git_rpc.git", branch: "master"
# gem "rugged", git: "http://rnd-isourceb.huawei.com/code/rugged.git", branch: "master", submodules: true
gem 'rugged'

gem 'gitlab_git', git: "https://code.csdn.net/CSDN_Dev/gitlab_git.git", branch: "csdnv1.0"

group :development do
  gem 'rubocop'
  gem 'coveralls', require: false
  gem "rspec", "~>2.14.1"
  gem 'webmock'
  gem 'guard'
  gem 'guard-rspec'
  gem 'pry'
  gem 'rake'
end

group :test do
  gem 'simplecov', require: false
end
