#encoding: utf-8
require 'drb'
require 'pathname'
require 'benchmark'

module Gitlab
  module Git
    class DRbInterface
      extend RedisHelper
      def performance_test(repo_path,type="")
        result = ''
        t = Benchmark.realtime do
          case type
          when "memory"
            result = `free -m | grep buffers/cache`
          when "cpu"
            result = `sar -u 1 1 | grep Average`
          when "redis"
            result = Gitlab::Git::DRbInterface.route_redis
          else
          end
        end
        return [result, t]
      end

      def method_missing(class_with_action, *args, &block)
        class_with_action_arr = class_with_action.to_s.split(".")
        super if class_with_action_arr.size != 2
        clazz = class_with_action_arr.first.split('::').inject(Object) {|o,c| o.const_get c}
        clazz.send(class_with_action_arr.last, *args, &block)
      end

      def remote_commit_stats_new(path, commit)
        Gitlab::Git::CommitStats.new(commit)
      end

      def remote_commit_tree(repo_path,commit)
	commit.tree_rpc
      end

      def remote_merge_repo_add_fetch_source!(repo_path, source_repo_url, source_name, fetch_name)
        repo = Gitlab::Git::Repository.new(repo_path)
	Gitlab::Git::MergeRepo.add_fetch_source_to_target!(repo, source_repo_url, source_name, fetch_name)
      end
    end
  end
end
