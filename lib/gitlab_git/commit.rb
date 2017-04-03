# Gitlab::Git::Commit is a wrapper around native Rugged::Commit object
module Gitlab
  module Git
    class Commit
      include DiffsAnalysis
      undef_method :raw_commit

      attr_accessor :repo_path, :tree_oid
      class << self

        def where(options)
          repo = options.delete(:repo)
          raise 'Gitlab::Git::Repository is required' unless repo.respond_to?(:log)
          repo.log(options)
        end

        def find(repo, commit_id = "HEAD")
          return decorate_rpc(commit_id, repo.path) if commit_id.is_a?(Rugged::Commit)

          obj = repo.rev_parse_target(commit_id)
          decorate_rpc(obj, repo.path)
        rescue Rugged::ReferenceError, Rugged::InvalidError, Rugged::ObjectError
          nil
        end

        def between_rpc(repo, base, head, options={})
          limit, offset = options.delete(:limit), options.delete(:offset)
          commit_proc = options.delete(:proc)

          commits = repo.commits_between(base, head)
          commit_proc.call(commits) if commit_proc && commit_proc.is_a?(Proc)
          commits = commits[offset, limit] if limit && offset
          commits.map do |commit|
            decorate_rpc(commit, repo.path)
          end
        rescue => e #Rugged::ReferenceError
          []
        end

        def find_all(repo, options = {})
          repo.find_commits(options)
        end

        def decorate_rpc(commit, repo_path, ref = nil)
          if commit.is_a? Gitlab::Git::Commit
            return commit
          elsif commit.is_a? Array
            commit.map{|c| Gitlab::Git::Commit.new(c,repo_path,ref)}
          else
            Gitlab::Git::Commit.new(commit, repo_path, ref)
          end
        end

        def diff_from_parent_rpc(repo, commit_id, options = {})
          rugged_commit = repo.rev_parse_target(commit_id) rescue nil
          return {diffs_size: 0, diffs: []} unless rugged_commit

          options ||= {}
          break_rewrites = options[:break_rewrites]
          actual_options = Diff.filter_diff_options(options)

          if rugged_commit.parents.empty?
            diff = rugged_commit.diff(actual_options.merge(reverse: true))
          else
            diff = rugged_commit.parents[0].diff(rugged_commit, actual_options)
          end

          analysis_result = analysis_diffs(diff)
          diff.find_similar!(break_rewrites: break_rewrites)
          diff_size = diff.count

          offset, limit = options[:offset], options[:limit]
          diff = diff.to_a[offset, limit] if offset && limit
          diffs = diff.map { |d| Gitlab::Git::Diff.new(d) }

          return {diffs_size: diff_size, diffs: diffs, analysis_result: analysis_result}
        end

        def to_patch(repo,commit_id)
          raw_commit = repo.rugged.lookup(commit_id)
          raw_commit.nil? ? '' : raw_commit.to_mbox
        end

        def find_first_commit(options)
          repo = options.delete(:repo)

          actual_ref = options[:ref] || repo.root_ref
          ref_commit = repo.rev_parse_target(actual_ref)
          return nil if ref_commit.nil?

          path = options[:path]
          return Gitlab::Git::Commit.new(ref_commit, repo.path, actual_ref) if path.to_s == ""

          entrys_oid_array = path_entry_oids(repo, ref_commit, path)
          return nil if entrys_oid_array.nil?

          first_commit(repo, ref_commit, path, entrys_oid_array)
        end


        def first_commit(repo, commit, path, entrys_oid_array)
          same_flag = true
          pathname = Pathname.new(path)
          commits = []
          while same_flag
            commits = [commit]
            while commit.parents && commit.parents.size == 1
              commit = commit.parents.first
              commits << commit
            end

            same_flag, commit = if commit.parents.nil?
                                  commit_touches_path?(repo, commit, pathname, entrys_oid_array, false)
                                else
                                  commit_touches_path?(repo, commit, pathname, entrys_oid_array)
                                end

            return commit if commit.parents.nil? && same_flag
          end

          pre_size = 0
          now_size = commits.size
          while now_size / 2 > 2
            same_flag, commit = commit_touches_path?(repo, commits[pre_size + now_size - now_size/2 - 1], pathname, entrys_oid_array, false)
            if same_flag
              pre_size += now_size - now_size/2 - 1
              now_size = now_size - now_size/2
            else
              now_size = now_size - now_size/2 - 1
            end
          end

          same_flag = true
          now_commit = commits[pre_size]
          while same_flag
            same_flag, now_commit = commit_touches_path?(repo, now_commit, pathname, entrys_oid_array)
          end

          return now_commit
        end

        def commit_touches_path?(repo, commit, pathname, entrys_oid_array, is_parent= true)
          same_flag, now_commit = false, nil

          commits = is_parent ? commit.parents : [commit]
          return [false, commit] if is_parent && commit.parents.nil?

          commits.each do |par_commit|
            ind, tmp_entry = 0, nil
            now_commit = par_commit

            pathname.each_filename do |dir|
              if tmp_entry.nil?
                tmp_entry = par_commit.tree[dir]
              else
                tmp_entry = repo.rugged.lookup(tmp_entry[:oid])
                break unless tmp_entry.type == :tree

                tmp_entry = tmp_entry[dir]
              end

              if tmp_entry && entrys_oid_array[ind] == tmp_entry[:oid]
                same_flag = true
                break
              end
              ind += 1
            end
            break if same_flag
          end

          commit = now_commit if same_flag
          return same_flag, commit
        end

        def path_entry_oids(repo, commit, path)
          pathname = Pathname.new(path)
          tmp_entry = nil
          path_entry_oids = []
          pathname.each_filename do |dir|
            if tmp_entry.nil?
              tmp_entry = commit.tree[dir]
            else
              tmp_entry = repo.rugged.lookup(tmp_entry[:oid])
              return nil unless tmp_entry.type == :tree
              tmp_entry = tmp_entry[dir]
            end
            return nil if tmp_entry.nil?
            path_entry_oids << tmp_entry[:oid]
          end
          path_entry_oids
        end
      end

      def initialize(raw_commit, repo_path=nil, head = nil)
        raise "Nil as raw commit passed" unless raw_commit
        # raise "Nil as repo_path passed" unless repo_path

        if raw_commit.is_a?(Hash)
          init_from_hash(raw_commit)
        elsif raw_commit.is_a?(Rugged::Commit) || raw_commit.is_a?(DRb::DRbObject)
          init_from_rugged(raw_commit)
        else
          raise Rugged::InvalidError.new "Invalid raw commit type: #{raw_commit.class}"
        end

        @head = head
        if raw_commit.is_a?(Hash)
          raise ArgumentError.new("repo_path is not exist in hash") if raw_commit[:repo_path].nil?
          @repo_path = raw_commit[:repo_path]
        else
          raise ArgumentError.new "repo_path is not exist" if repo_path.nil?
          @repo_path = repo_path
        end
      end

      def diff_from_parent_rpc(options = {})
       Commit.diff_from_parent_rpc(repo, self.id, options)
      end

      def raw_commit
        repo.rugged.lookup(id)
      end

      def drb_name
        if repo_path || head
          "commit_with_path_head_#{Digest::SHA1.hexdigest("#{sha}_#{@repo_path}_#{@head}")}"
        else
          "commit_#{sha}"
        end
      end

      def repo
        return @repo unless @repo.nil?
        @repo = Gitlab::Git::Repository.new(@repo_path)
      end

      def to_patch
        Gitlab::Git::Commit.to_patch(repo,id)
      end

      def to_diff
        patch = to_patch

        # discard lines before the diff
        lines = patch.split("\n")
        while lines.first!=nil && !lines.first.start_with?("diff --git") do
          lines.shift
        end
        lines.pop if lines.last =~ /^[\d.]+$/ # Git version
        lines.pop if lines.last == "-- " # end of diff
        lines.join("\n")
      end

      def diffs_rpc(options = {})
        Commit.diff_from_parent_rpc(repo, self.id, options)
      end

      def parents_rpc(raw_commit)
        return @parents unless @parents.nil?
        @parents = raw_commit.parents.map { |c| Gitlab::Git::Commit.new(c, @repo_path) }
      end

      def tree_rpc
      	tree = self.tree  
        Gitlab::Git::Tree.new({id: tree_oid, root_id: tree_oid, type:tree.type, path: '', commit_id: self.id, repo_path: repo_path})
      end

      def refs_rpc
        repo.refs_hash[id]
      end

      def remote_ref_names
        ref_names_rpc
      end

      def ref_names_rpc
        refs_rpc.map do |ref|
          ref.name.sub(%r{^refs/(heads|remotes|tags)/}, "")
        end
      end

      #add
      def utf8_message
        encode! self.message
      end

      # return a hash
      def author
        {:name=>self.author_name, :email=>self.author_email, :time=>self.authored_date, :utf8_email=>encode!(self.author_email), :utf8_name=>encode!(self.author_name)}
      end

      def committer
        {:name=>self.committer_name, :email=>self.committer_email, :time=>self.committed_date, :utf8_email=>encode!(self.committer_email), :utf8_name=>encode!(self.committer_name)}
      end

      def self.list_from_string(repo, text)
        lines = text.split("\n")

        commits = []

        while !lines.empty?
          id = lines.shift.split.last
          # tree = lines.shift.split.last

          parents = []
          parents << lines.shift.split.last while lines.first =~ /^parent/

          author_line = lines.shift
          author_line << lines.shift if lines[0] !~ /^committer /
          # author, authored_date = self.actor(author_line)

          committer_line = lines.shift
          committer_line << lines.shift if lines[0] && lines[0] != '' && lines[0] !~ /^encoding/
          # committer, committed_date = self.actor(committer_line)

          # not doing anything with this yet, but it's sometimes there
          encoding = lines.shift.split.last if lines.first =~ /^encoding/

          lines.shift

          message_lines = []
          message_lines << lines.shift[4..-1] while lines.first =~ /^ {4}/

          lines.shift while lines.first && lines.first.empty?
          raw = Gitlab::Git::Commit.find(repo, id)
          commits << Gitlab::Git::Commit.new(raw, repo.path)
        end

        commits
      end

      def rugged_tree
        entry_hash={}
        @entries.each { |e| entry_hash[e[:name]] = e }
        entry_hash
      end

      private

      def init_from_hash(hash)
        raw_commit = hash.symbolize_keys

        serialize_keys.each do |key|
          send("#{key}=", raw_commit[key])
        end
      end

      def init_from_rugged(commit)
        # @raw_commit = commit
        @id = commit.oid
        @message = commit.message
        @authored_date = commit.author[:time]
        @committed_date = commit.committer[:time]
        @author_name = commit.author[:name]
        @author_email = commit.author[:email]
        @committer_name = commit.committer[:name]
        @committer_email = commit.committer[:email]
        @parent_ids = commit.parents.map(&:oid)
        tree = commit.tree
        @tree_oid = tree.oid
        @entries = tree.entries
      end

      def serialize_keys
        SERIALIZE_KEYS + [:tree_oid]
      end
    end
  end
end
