require 'redis'
require 'redis-store'
require 'digest/sha1'

module Gitlab
  module Git
    class MergeRepo
      DEFAULT_CACHE_MUN = Gitlab::Git::Settings.merge_repo.default_cache_num
      DEFAULT_PATCH_PATH = Gitlab::Git::Settings.merge_repo.default_patch_path
      DIFF_COMMIT_CACHE_DEFAULT_TIME = Gitlab::Git::Settings.merge_repo.diff_commit_cache_default_time

      include DRb::DRbUndumped
      include DiffsAnalysis
      extend  Gitlab::Git::RedisHelper

      attr_accessor :server, :repo

      def self.commits_and_diffs(repo_path, target_name, source_name, source_repo_path=nil, options={})
        defalt_option = {offset: 0, limit: 10, type: "all", conflict_test_flag: false}

        options = defalt_option.merge(options)
        results = {}

        use_cache = options[:use_cache] || true
        key = get_hash_name_and_key(repo_path, target_name, source_name, source_repo_path, options[:is_oid])
        if options[:offset]+options[:limit]<=DEFAULT_CACHE_MUN && use_cache && merge_repo_cached?(key)
          return {} unless merge_repo_cached?(key)
          results = redis_server.get(key)

          base, head = undeclare([results[:base], results[:head]])
          diffs = undeclare(results[:diffs])
          commits = undeclare(results[:commits])

          results.merge!({head: head, base: base, diffs: diffs, commits: commits})
        else
          execute(repo_path, target_name, source_name, source_repo_path) do |merge_repo|
            results = if options[:type]=="diffs"
                        merge_repo.diffs(options[:offset], options[:limit], true)
                      elsif options[:type]=="commits"
                        merge_repo.commits(options[:offset], options[:limit])
                      else
                        merge_repo.diffs_and_commits(options[:offset], options[:limit], true)
                      end
         
            results[:base], results[:head] = merge_repo.base, merge_repo.head
            results[:merge_conflicts?] = merge_repo.merge_conflicts? if options[:conflict_test_flag]
          end
        end

        return results
      end

      def self.save_patch(repo_path, target_name, source_name, source_repo_path=nil, options={})
        result = [false, nil, nil]
        return result if options[:patch_name].nil?
        Gitlab::Git::MergeRepo.execute(repo_path, target_name, source_name, source_repo_path) do |merge_repo|
          result = [merge_repo.save_patch(options[:patch_name]), merge_repo.head.id, merge_repo.base.id]
        end
        return result
      end

      def self.merge_conflict_files(repo_path, target_name, source_name, source_repo_path=nil, options={})
         merge_conflict_files = []
         Gitlab::Git::MergeRepo.execute(repo_path, target_name, source_name, source_repo_path) do |merge_repo|
           merge_conflict_files = merge_repo.merge_conflict_files
         end
         return merge_conflict_files
      end

      def self.conflict_merge!(repo_path, target_name, source_name, source_repo_path=nil, options={})
        username, useremail, resolve_hash = options[:username], options[:useremail], options[:resolve_hash]
        status = false
        Gitlab::Git::MergeRepo.execute(repo_path, target_name, source_name, source_repo_path) do |merge_repo|
          return false if merge_repo.lock?
          begin
            merge_repo.lock
            status = merge_repo.merge_conflicts!(username, useremail, "Page merge by code", resolve_hash)
          ensure
            merge_repo.unlock
          end
        end
        #repo sync msg
        # ProjectSyncClient.push repo_path, 'push' if status
        return status
      end

      def self.automerge!(repo_path, target_name, source_name, source_repo_path=nil, options={})
        result = []
        username, useremail = options[:username], options[:useremail]
        message = options[:message]
        reverse_flag = options[:reverse_flag]
        Gitlab::Git::MergeRepo.execute(repo_path, target_name, source_name, source_repo_path) do |merge_repo|
          return [false, 'Another MR just merged at the same time, please try again.'] if merge_repo.lock?
          begin
            merge_repo.lock
            result = merge_repo.merge!(username, useremail, message, reverse_flag)
          ensure
            merge_repo.unlock
          end
        end
        #repo sync msg
        # ProjectSyncClient.push repo_path, 'push'
        return result
      end

      def self.cache(repo_path, target_name, source_name, source_repo_path=nil, options={})
        offset = options[:offset] || 0
        limit = options[:limit] || 20
        use_cache = options[:use_cache].nil? ? true : options[:use_cache] 
        key = get_hash_name_and_key(repo_path, target_name, source_name, source_repo_path, options[:is_oid])

        if offset+limit<=DEFAULT_CACHE_MUN && use_cache && merge_repo_cached?(key)
          return {} unless merge_repo_cached?(key)
          @cached_merge_repo = redis_server.get(key)

          base, head = undeclare([@cached_merge_repo[:base], @cached_merge_repo[:head]])
          diffs = undeclare(@cached_merge_repo[:diffs])
          commits = undeclare(@cached_merge_repo[:commits])

          @cached_merge_repo = @cached_merge_repo.merge!({head: head, base: base, diffs: diffs, commits: commits})
        else
          execute(repo_path, target_name, source_name, source_repo_path) do |merge_repo|
            @cached_merge_repo = if offset+limit > DEFAULT_CACHE_MUN
                                   merge_repo.diffs_and_commits(offset, limit, true)
                                 else
                                   merge_repo.diffs_and_commits(0, DEFAULT_CACHE_MUN, true)
                                 end
            @cached_merge_repo = {same: merge_repo.same, head: merge_repo.head, base: merge_repo.base, merge_conflicts?: merge_repo.merge_conflicts?}.merge(@cached_merge_repo)
	    return @cached_merge_repo if @cached_merge_repo[:same]

            if offset+limit <= DEFAULT_CACHE_MUN

              base, head = declare([@cached_merge_repo[:base], @cached_merge_repo[:head]])
              diffs = declare(@cached_merge_repo[:diffs])
              commits = declare(@cached_merge_repo[:commits])
              cache = @cached_merge_repo.merge(base: base, head: head, diffs: diffs, commits: commits)

              redis_server.set(key, cache)
              redis_server.expireat(key, (Time.now + DIFF_COMMIT_CACHE_DEFAULT_TIME).to_i)
            end
          end
        end


        if offset+limit <= DEFAULT_CACHE_MUN
          diffs = @cached_merge_repo[:diffs].to_a[offset, limit]
          commits = @cached_merge_repo[:commits].to_a[offset, limit]
          @cached_merge_repo.merge!({diffs: diffs, commits: commits})
        end
        @cached_merge_repo
      end

      def self.commits_check(repo_path, target_name, source_name, options, source_repo_path=nil)
        result = nil
        execute(repo_path, target_name, source_name, source_repo_path) do  |merge_repo|
          result = merge_repo.repo.commits_check(merge_repo.base.try(:id), merge_repo.head.try(:id), options)
        end
        return result
      end

      def self.execute(repo_path, target_name, source_name, source_repo_path=nil)
        same_repo = (source_repo_path.nil? || source_repo_path==repo_path) ? true : false
        repo = Gitlab::Git::Repository.new(repo_path)
        unless same_repo
          user_repo_path = source_repo_path.gsub(/[^\w\/_\-\.]/, '-')
          fetch_name = "merges/#{user_repo_path}/#{source_name}"
          full_source_repo_path = File.join(Settings.repository.pre_path, source_repo_path)
          add_fetch_source!(repo, full_source_repo_path, source_name, fetch_name)
          source_name = fetch_name
        end
        merge_repo = self.new(repo, target_name, source_name)
        yield(merge_repo) if block_given?
        return merge_repo
      end

      def initialize(repo, target_name, source_name)
        @repo = repo
        @source_name, @target_name = source_name, target_name
        @base = Gitlab::Git::Commit.find(repo, target_name)
        @head = Gitlab::Git::Commit.find(repo, source_name)
        @same = (@base.id == @head.id)
      end

      def compare
        @compare ||= Compare.new(@repo, @base.id, @head.id)
      end

      def lock
        Gitlab::Git::MergeRepo.redis_server.hset(repo.path, "#{target_branch}-#{source_branch}", true)
      end

      def unlock
        Gitlab::Git::MergeRepo.redis_server.hdel(repo.path, "#{target_branch}-#{source_branch}")
      end

      def lock?
        Gitlab::Git::MergeRepo.redis_server.hget(repo.path, "#{target_branch}-#{source_branch}") == 'true'
      end

      def target_branch
        @target_name
      end

      def source_branch
        @source_name
      end

      def head
        @head
      end

      def base
        @base
      end

      def same
        @same
      end

      def method_missing(method, *args, &block)
        method_array = method.to_s.split('_')
        if method_array.include? 'remote'
          send (method_array-['remote']).join('_'), *args, &block
        else
          raise ArgumentError.new("no method called:#{method}")
        end
      end

      def merge_conflicts?
        return false if @same

        @repo.merge_conflicts?(source_branch, target_branch)
      end

      def merge!(author_name, author_email, message, reverse_flag= false)
        ahead, behind = repo.rugged.ahead_behind(target_branch, source_branch)
        return [false, 'no ahead commits to merge'] if behind == 0

        # Do not generate a Merge commit, if:
        #  * can be fast-forwarded (ahead == 0) and
        #  * only have one commit in the merge request (behind == 1), or
        #  * is a reverse merge (is_reverse_merge == true)
        if ahead == 0 and (behind == 1 and reverse_flag)
          begin
            newrev_oid = repo.create_or_update_reference("refs/heads/#{target_branch}", head.id, base.id)
            return [true, [base.id, newrev_oid]]
          rescue Exception => e
            return [false, "Another MR just merged at the same time, please try again. (Cannot update #{target_branch} from #{base.id} to #{head.id}, detail: #{e.message})"]
          end
        else
          begin
            merge_params = if reverse_flag
                             [target_branch, source_branch]
                           else
                             [source_branch, target_branch]
                           end
            index, parents = repo.merge_index_with_commits(*merge_params)
            return [false, 'Can`t merge, has conflicts'] if index.conflicts?

            full_message =  message.to_s + other_message_from_commits(reverse_flag)
            author = {:email => author_email.to_s, :time => Time.now + 1, :name => author_name.to_s}
            options = {:author => author, :message => full_message, :committer => author}
            options[:parents] = parents.map(&:oid)
           
            newrev_oid = repo.merge_commit(index, target_branch, options)
            return [true, [base.id, newrev_oid]]
         
          rescue => e
            return [false, "Another MR just merged at the same time, please try again. (Cannot merge #{target_branch} from #{base.id} to #{head.id}, detail: #{e.message})"]
          end
        end
      end


      def merge_patch!(patch_name)
        use_patch(patch_name)
      end

      def merge_conflicts!(author_name, author_email, message, resolve_hash)
        index, parents = repo.merge_index_with_commits(source_branch, target_branch)
        resolve_hash.each do |filename, option|
          filename = filename.to_s
          conflict = index.conflict_get(filename)
          next unless conflict

          index.conflict_remove(filename)
          case option[:type]
            when "edit"
              new_blob = repo.rugged.write(option[:content], :blob)
              entry = conflict[:ours]
              entry[:stage] = 0
              entry[:oid] = new_blob
              index.add(entry)
            when "add"
              entry = conflict[:ours] || conflict[:theirs]
              entry[:stage] = 0
              index.add(entry)
            when "add_them"
              entry = conflict[:theirs]
              entry[:stage] = 0
              index.add(entry)
            when "add_us"
              entry = conflict[:ours]
              entry[:stage] = 0
              index.add(entry)
            when "add_both"
              entry_ours, entry_theirs = conflict[:ours], conflict[:theirs]
              entry_ours[:stage] = 0
              entry_theirs[:stage] = 0
              if option[:rename] == 'us'
                entry_ours[:path] = option[:file_name]
              else
                entry_theirs[:path] = option[:file_name]
              end
              index.add(entry_ours)
              index.add(entry_theirs)
          end
        end
        return false if index.conflicts?

        author = {:email => author_email.to_s, :time => Time.now, :name => author_name.to_s}
        options = {:author => author, :message => message.to_s, :committer => author, :parents => parents}

        @repo.merge_commit(index, @target_name, options)
        #repo sync msg
        # ProjectSyncClient.push repo.path, 'push'
        return true
      end

      def merge_index
        @indxe ||= repo.merge_index(source_branch, target_branch)
      end

      def merge_conflict_files
        files_arr = []
        merge_index.conflicts.each do |conflict|
          if conflict[:ancestor] && conflict[:ours] && conflict[:theirs]
            path = conflict[:ancestor][:path]
            files_arr << {path: path, type: "modify", content: merge_index.merge_file(path)}
          elsif conflict[:ancestor].nil? && conflict[:ours] && conflict[:theirs]
            path = conflict[:ours][:path]
            files_arr << {path: path, type: "add_both", content: merge_index.merge_file(path)}
          else
            path = conflict[:ours][:path] || conflict[:theirs][:path]
            files_arr << {path: path, type: "delete_modify", content: merge_index.merge_file(path)}
          end
        end
        return files_arr
      end

      def diffs(offset=0, limit=20, analysis_flag=false)
        return {timeout_diffs: false, diffs: [], diffs_size: 0, analysis_result: {}} if @same

        options = {offset: offset, limit: limit}
        analysis_result = {}
        diff_size = 0
        options[:proc] = Proc.new do |diff|
          analysis_result = analysis_diffs(diff) if analysis_flag
        end

        diffs, diff_size = compare.diffs(nil, options)

        {timeout_diffs: compare.timeout_diffs, diffs: diffs, diffs_size: diff_size, analysis_result: analysis_result}
      end

      def commits(offset=0, limit=20)
        return {timeout_commits: false, commits: [], commits_size: 0} if @same

        options = {offset: offset, limit: limit}
        commits_size = 0
        options[:proc] = Proc.new do |commits|
          commits_size = commits.size
        end

        commits = compare.commits(options)
        {timeout_commits: compare.timeout_commits, commits: commits, commits_size: commits_size}
      end

      def diffs_and_commits(offset=0, limit=20, analysis_flag=false)
        diffs = diffs(offset, limit, analysis_flag)
        commits = commits(offset, limit)
        diffs.merge(commits)
      end

      def save_patch(patch_name)
        diffs, status = repo.format_patch_by_cmd(base.id, head.id)
        # diffs = compare.diffs(nil, {}).to_s
        return false unless status
        begin
          patch_dir = "#{DEFAULT_PATCH_PATH.to_s}#{patch_name}"
          patch_name_arr = patch_dir.split("/")
          (patch_name_arr.size-1).times do |i|
            dir = patch_name_arr[0, i+1].join("/")
            next if dir.to_s == ""
            Dir.mkdir(dir) unless Dir.exists?(dir)
          end

          File.open(patch_dir, 'w+') do |patch|
            patch.write(diffs)
          end
        rescue => error
          status = false
        end
        status
      end

      def self.get_patch(patch_name)
        File.new("#{DEFAULT_PATCH_PATH.to_s}#{patch_name}", 'r')
      end

      private
      def self.add_fetch_source!(repo, source_repo_url, source_name, fetch_name)
        repo.fetch_rpc(source_repo_url, "+#{source_name}:refs/#{fetch_name}", "--no-tags --quiet --force")
      end

      def self.merge_repo_cached?(key)
        redis_server.exists(key)
      end

      def other_message_from_commits(reverse_flag)
        other_message = ''
        if reverse_flag
          other_message << get_message_from_commits(base, head)
          other_message << "\n* Changes of local (#{repo.path.sub(/.git$/, '')}::#{target_branch}):\n"
          other_message << get_message_from_commits(head, base)
        else
          other_message = get_message_from_commits(head, base)
        end
      end

      def get_message_from_commits(head_commit, base_commit)
        messages = [nil]
 
        walker = Rugged::Walker.new(repo.rugged)
        walker.push_range("#{base_commit.id}..#{head_commit.id}")
        walker.each(offset: 0, limit: 21) do |commit|
          messages << "  " + commit.message.split("\n").first rescue ''
        end
        messages[-1] = "  ... ..." if messages.size == 22
 
        return messages.join("\n")
      #rescue
      #  ""
      end


      def self.get_hash_name_and_key(repo_path, target_name, source_name, source_repo_path, is_oid=false)
        if is_oid
          Digest::SHA1.hexdigest("#{repo_path.to_s.strip}_#{source_repo_path.to_s.strip}_#{target_name}_#{source_name}")
        else
          if source_repo_path.nil?
            compare = Compare.new(Gitlab::Git::Repository.new(repo_path), target_name, source_name)
            base, head=[compare.base, compare.head]
          else
            base = Gitlab::Git::Commit.find(Gitlab::Git::Repository.new(repo_path), target_name.try(:strip))
            head = Gitlab::Git::Commit.find(Gitlab::Git::Repository.new(source_repo_path), source_name.try(:strip))
          end
          Digest::SHA1.hexdigest("#{repo_path.to_s.strip}_#{source_repo_path.to_s.strip}_#{base.id}_#{head.id}")
        end
      end

      def self.redis_server
        @server ||= local_cache_redis
      end

      def use_patch(patch_name)
        patch_path = "#{DEFAULT_PATCH_PATH}#{patch_name}"
        @repo.use_patch(patch_path)
      end

      def push
        @repo.push("origin", "refs/heads/#{@target_name}")
      end

      def self.declare(arr)
        objs = []
        arr.each do |obj|
          if obj.nil?
            objs << nil
            next
          end

          instance_variables = {}
          obj.instance_variables.each do |key|
            value = obj.instance_variable_get(key)
            next if value.class.name =~ /^Rugged\:\:/
            key = key.to_s.sub(/^@/, '').to_sym

            instance_variables[key] = value
          end

          objs << {class_name: obj.class.name, instance_variables: instance_variables}
        end
        return objs
      end

      def self.undeclare(arr)
        objs = []
        arr.each do |obj|
          if obj.nil?
            objs << nil
            next
          end

          objs << eval("#{obj[:class_name]}").new(obj[:instance_variables])
        end
        return objs
      end
    end
  end
end
