if ENV['TRAVIS']
  require 'coveralls'
  Coveralls.wear!
else
  require 'simplecov'
  SimpleCov.start
end

require 'gitlab_git_server'
require 'pry'
require 'benchmark'

require_relative 'support/seed_helper'
require_relative 'support/commit'
require_relative 'support/first_commit'
require_relative 'support/last_commit'
require_relative 'support/big_commit'
require_relative 'support/ruby_blob'
require_relative 'support/repo'

RSpec::Matchers.define :be_valid_commit do
  match do |actual|
    actual != nil
    actual.id == SeedRepo::Commit::ID
    actual.message == SeedRepo::Commit::MESSAGE
    actual.author_name == SeedRepo::Commit::AUTHOR_FULL_NAME
  end
end

SUPPORT_PATH = File.join(Gitlab::Git::Server::PRE_PATH,'code_test')
TEST_REPO_PATH = 'code_test/gitlab-git-test.git'
TEST_REPO_URL = 'https://code.csdn.net/liuhq002/gitlab-git-test.git'
TEST_NORMAL_REPO_PATH = 'code_test/not-bare-repo.git'
TEST_MUTABLE_REPO_PATH = 'code_test/mutable-repo.git'
MERGE_PATH = 'code_test/merge.git'
# FULL_TEST_REPO_PATH = File.join(SUPPORT_PATH, TEST_REPO_PATH)
# TEST_NORMAL_REPO_PATH = File.join(SUPPORT_PATH, "code_test/not-bare-repo.git")
# TEST_MUTABLE_REPO_PATH = File.join(SUPPORT_PATH, "code_test/mutable-repo.git")

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus
  config.order = 'random'
  config.include SeedHelper
  config.before(:all) { ensure_seeds }
end
class TestBenchmark
  def self.cost(message,path,time=nil)
    if time.nil?
      system("echo '#{message}' > '#{path}'")
    else
      system("echo '#{message} costs #{time*1000} ms' >> '#{path}'")
    end
  end
end
# class TestBenchmark < Spec::Benchmark
#
# end
