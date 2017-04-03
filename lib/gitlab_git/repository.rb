require 'pathname'
module Gitlab
  module Git
    class Repository
      include DRb::DRbUndumped
      include EncodingHelper
      extend RedisHelper
      extend Gitlab::Git::Popen
      TIME_OUT_TIME = 240
      attr_reader :full_path

      def self.set_write_methods
        [:archive_repo, :merge_base_commit, :reset, :checkout, :delete_branch, :remote_delete, :remote_add, :remote_update, :fetch, :fetch_rpc, :push, :format_patch, :merge, :autocrlf=,:create_branch, :create_tag, :delete_tag, :create_reference, :delete_reference, :update_reference, :create_or_update_reference, :format_patch_by_cmd, :use_patch, :merge_index, :merge_index_with_commits, :merge_commit, :rename, :delete, :change_owner, :rename, :delete, :change_owner, :fork, :update_head]
      end

      def self.set_create_methods
        [:init, :import]
      end
      
      def self.to_sym
        'repository'.to_sym
      end
      # init a repository
      # eg: Gitlab::Git::Repository.init('john/new_repo_name')
      # will init new_repo_name.git
      def self.init(path_with_namespace, bare=true)
        path_array = path_with_namespace.split('/')
        config_path = Gitlab::Git::Server::PRE_PATH
        raise NoRepository.new('path must be like:xx/yy.git') unless (path_array-['','.git']).compact.size==2
        user_name, repo_name = path_array.first, path_array.last
        repo_pre_path = File.join(config_path,user_name)
        repo_full_path = File.join(repo_pre_path,repo_name)
        Dir.mkdir(repo_pre_path) unless File.exist?(repo_pre_path)
        cmd = bare ? "git init --bare '#{repo_name}'" : "git init '#{repo_name}'"
        output, status = popen([cmd], repo_pre_path)
        self.add_hooks(path_with_namespace) if bare && status
        #ProjectSyncClient.push path_with_namespace, 'create' if status
        return status
      end

      def self.rename(name_with_path, new_name_with_path)
        user_name, repo_name = name_with_path.split('/')
        output, status = popen(["mv '#{name_with_path}' '#{new_name_with_path}'"], Gitlab::Git::Server::PRE_PATH)

        #repo sync msg
        #ProjectSyncClient.push new_name_with_path, 'rename', name_with_path if status
        return status
      end

      def self.delete(name_with_path)
        user_name, repo_name = name_with_path.split('/')
        pre_path = File.join(Gitlab::Git::Server::PRE_PATH, user_name)

        output, status = popen(["mv '#{repo_name}' '#{repo_name}.del.#{Time.now.to_i}'"], pre_path)
        #repo sync msg
        # if status
        #   ProjectSyncClient.push name_with_path, 'delete'
        # end
        return status
      end

      def self.change_owner(name_with_path, new_owner_name)
        user_name, repo_name = name_with_path.split('/')
        pre_path = Gitlab::Git::Server::PRE_PATH
        new_owner_path = File.join(pre_path, new_owner_name)
        popen(["mkdir  #{new_owner_name}"], pre_path)  unless File.exist?(new_owner_path)
        output, status = popen(["mv '#{name_with_path}' '#{new_owner_name}'"], pre_path)
        # ProjectSyncClient.push "#{new_owner_name}/#{repo_name}", 'rename', name_with_path if status
        return status
      end

      def self.fork(name_with_path, source_name_with_path)
        import(name_with_path, File.join(Gitlab::Git::Server::PRE_PATH, source_name_with_path), 'git', true)
        return 0
      end

      def self.import(name_with_path, url, type='git', is_fork = false)
        #do with worker
        front_cache_redis.hset('backend_doing_queue', name_with_path, true)
        Gitlab::Git::Workers::ForkWorker.perform_async(name_with_path, url, type, is_fork)
      end

      def self.update_head(name_with_path, head)
        repo = self.new(name_with_path)
        if head and head.start_with?('refs/heads/')
          head = head[11..-1] # 'refs/heads/'.size == 11
        end

        result = if head and not head.empty?
                   repo.update_reference('HEAD', "refs/heads/#{head}")
                   [nil, true]
                 else
                   ["Can not update_head with bad reference: #{head}", false]
                 end

        #repo sync msg
        # ProjectSyncClient.push name_with_path, 'push'
        result
      end

      #目前是把后端的code-shell目录下的hooks目录软链到仓库下的hooks目录了，之前仅仅是针对post-receive 和 update文件软链过去了
      def self.add_hooks(name_with_path)
        repo_hooks_path = File.join(Gitlab::Git::Server::PRE_PATH, name_with_path, 'hooks')
        hooks_path = Settings.git_hooks_dir
        if File.realpath(repo_hooks_path) != File.realpath(hooks_path)
          if File.symlink? repo_hooks_path
            File.unlink repo_hooks_path
          else
            FileUtils.mv(repo_hooks_path, "#{repo_hooks_path}.old.#{Time.now.to_i}")
          end
          FileUtils.ln_s(hooks_path, repo_hooks_path)
        end
      end

      # remote_update is something wrong
      def initialize(path)
        @path = path
        @name = path.split("/").last
        raise NoRepository.new('no repository for such path') unless check_repo_present?    
        Gitlab::Git::CacheHost.set_cache_host(path)
      end

      def check_repo_present?
        File.exist?(full_path)
        #output, status = popen(["git rev-parse --is-inside-git-dir"], full_path)
        #return status == 0 && output.to_s.strip == 'true'
      end


      #重写这些方法，发送同步消息
      %W(reset remote_delete remote_add fetch push merge autocrlf=).each do |m|
        alias_method "#{m}_old", m 
        define_method "#{m}" do |*args, &block|
          result = send("#{m}_old", *args, &block)
          #repo sync msg
          # ProjectSyncClient.push send(:path), 'push'
          result
        end 
      end

      def full_path
        @full_path ||= File.join(Gitlab::Git::Server::PRE_PATH, path)
      end

      def readme(branch = 'master')
        commit = self.lookup(branch)
        tree = commit.tree
        readmes = tree.entries.find_all { |c| c[:type]==:blob and c[:name] =~ /^readme/i }
        if readmes and readmes.count > 1
          readmes.sort_by! do |r|
            path = Pathname.new r[:name]
            case path.extname
              when /\.markdown/i
                1
              when /\.md/i
                0
              else
                2
            end
          end
          readme = readmes[0]
        else
          readme = readmes[0] if !readmes.empty? and readmes.count == 1
        end
        if readme
          blob = self.lookup(readme[:oid])
          Gitlab::Git::Blob.new(
              id: blob.oid,
              name: readme[:name],
              size: blob.size,
              data: blob.content,
              mode: readme[:mode],
              path: readme[:name],
              commit_id: commit.oid,
          )
        else
          nil
        end
      end


      def rugged
        @rugged ||= Rugged::Repository.new(full_path)
      rescue Rugged::RepositoryError, Rugged::OSError
        Gitlab::Git::CacheHost.delete_cache_host(path)
        raise NoRepository.new('no repository for such path')
      end

      def branches
        #return @branches unless @branches.nil?
        result = rugged_branches.map do |rugged_ref|
          Branch.new(rugged_ref.name, rugged_ref.target)
        end
        @branches = result.sort_by(&:name)
      end

      def branch_details
        refs_cache = {}
        bs = self.branches
        bs.size.times do |i| 
          ref = bs[i]
          commit = self.commit(ref.target)
          refs_cache[commit.id] = [] unless refs_cache.include?(commit.id)
          refs_cache[commit.id] << ref 
        end 
        refs_cache
      end


      def tags
        #return @tags unless @tags.nil?
        @tags = rugged_references.each("refs/tags/*").map do |ref|
          message = nil

          if ref.target.is_a?(Rugged::Tag::Annotation)
            tag_message = ref.target.message

            if tag_message.respond_to?(:chomp)
              message = tag_message.chomp
            end
          end

          Gitlab::Git::Tag.new(ref.name, ref.target, message)
        end
        @tags = @tags.sort_by(&:name)
      end


      def commits_between(from, to, sort=nil)
        walker = Rugged::Walker.new(rugged)
        from = rugged.rev_parse_oid(from)
        to = rugged.rev_parse_oid(to)
        walker.push(to)
        walker.hide(from)
        # walker.sorting(Rugged::SORT_DATE | Rugged::SORT_REVERSE)
        walker.sorting(sort) if sort
        commits = walker.to_a
        walker.reset
        commits.reverse
      end

      def commits_between_rpc(from, to, options={limit:50,offset:0})
          return [] if from.nil? || to.nil?
          begin
            ::Timeout.timeout(TIME_OUT_TIME) do
              Gitlab::Git::Commit.between_rpc(self, from, to, options)
            end
          rescue ::Timeout::Error => ex
            []
          end
      end

      def commits_between_include?(from, to, commit_ids=[])
        has_commit_ids = []
        commit_ids = commit_ids.uniq.compact
        return has_commit_ids if commit_ids.empty?

        from = rugged.rev_parse_oid(from) rescue nil
        to = rugged.rev_parse_oid(to) rescue nil
        return has_commit_ids if from.nil? || to.nil?

        walker = Rugged::Walker.new(rugged)
        walker.push(to)
        walker.hide(from)
        walker.each do |commit|
          has_commit_ids << commit.oid if commit_ids.include?(commit.oid)
          break if has_commit_ids.size == commit_ids.size
        end
        walker.reset
        return has_commit_ids
      end

      def format_patch(from, to, options = {})
        options ||= {}
        break_rewrites = options[:break_rewrites]
        actual_options = Diff.filter_diff_options(options)
        commits_between(from, to).map do |commit|
          commit.to_mbox(actual_options)
        end.join("\n")
      end

      def heads
        return @heads unless @heads.nil?
        @heads = rugged_references.each("refs/heads/*").map do |head|
          Gitlab::Git::Ref.new(head.name, head.target)
        end
        @heads = @heads.sort_by(&:name)
      end

      def commit_count(ref,path=nil)
        if path
          rev_list({ref: ref,path: path}).size
        else
          walker = Rugged::Walker.new(rugged)
          walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE)
          # ref = "refs/heads/#{ref}" unless ref.index('refs/heads/')
          ref = rugged.rev_parse_oid(ref)
          walker.push(ref)
          walker.count
        end
      end

      def checkout(ref, options = {}, start_point = "HEAD")
        if options[:b]
          rugged.branches.create(ref, start_point)
          options.delete(:b)
        end
        result = rugged.checkout(ref, options)
        #repo sync msg
        # ProjectSyncClient.push path, 'push'
        result 
      end

      def remote_update(remote_name, options = {})
        # TODO: Implement other remote options
        # Remote#clear_refspecs and Remote#save were removed without replacement.
        # Remote#url= and Remote#push_url= were removed and replaced by RemoteCollection#set_url and RemoteCollection#set_push_url.
        # Remote#add_push and Remote#add_fetch were removed and replaced by RemoteCollection#add_push_refspec and
        # RemoteCollection#add_fetch_refspec.
        if options[:url]
          remote_delete(remote_name)
          remote_add(remote_name, options[:url])
        end
      end

      # Fetch the specified remote
      def fetch_rpc(url, remote_name, *refspecs)
        git_fetch_cmd = %W(git --git-dir=#{full_path} fetch)
        git_fetch_cmd << refspecs.join(" ") unless refspecs.empty?
        git_fetch_cmd << url
        git_fetch_cmd << remote_name
        out_put, status = popen([git_fetch_cmd.join(" ")], full_path)
        return status
      end

      def find_commits(options = {})
        actual_options = options.dup

        allowed_options = [:ref, :max_count, :skip, :contains, :order]

        actual_options.keep_if do |key|
          allowed_options.include?(key)
        end

        default_options = {skip: 0}
        actual_options = default_options.merge(actual_options)

        walker = Rugged::Walker.new(rugged)

        if actual_options[:ref]
          walker.push(rugged.rev_parse_oid(actual_options[:ref]))
        elsif actual_options[:contains]
          branches_contains(actual_options[:contains]).each do |branch|
            walker.push(branch.target_id)
          end
        else
          rugged_references.each("refs/heads/*") do |ref|
            walker.push(ref.target_id)
          end
        end

        if actual_options[:order] == :topo
          walker.sorting(Rugged::SORT_TOPO)
        else
          walker.sorting(Rugged::SORT_DATE)
        end

        commits = []
        offset = actual_options[:skip]
        limit = actual_options[:max_count]
        walker.each(offset: offset, limit: limit) do |commit|
          gitlab_commit = Gitlab::Git::Commit.decorate_rpc(commit, self.path)
          commits.push(gitlab_commit)
        end

        walker.reset

        commits
      rescue Rugged::OdbError
        []
      end

      def commits_check(from, to, options)
        result = {}
        walker = Rugged::Walker.new(rugged)
      
        from = rugged.rev_parse_oid(from) #rescue nil if from
        to = rugged.rev_parse_oid(to) #rescue nil
        p from, to
        return {type: 'newrev', message: "Can't find new refs"} unless to && from

        walker.push(to)
        walker.hide(from) unless from
        walker.each do |commit|
           next if commit.parents.count != 1
           result = rugged_commit_check(commit, options)
           break unless result.empty?
        end
        walker.reset
        return result
      end

      def rugged_commit_check(commit, options)
        commits_regexp = options[:commits_regexp]
        diffs_file_name, diffs_file_size  = options[:file_name], options[:file_size]

        commits_regexp.each do |key, reg| 
          method, hash_key = key.to_s.split('_')
          result = commit.send(method.to_sym)
          result = result.fetch(hash_key.to_sym) if hash_key
          return {type: key, commit_id: commit.oid} if result !~ reg
        end

        if diffs_file_name || diffs_file_size
          commit.parents.first.diff(commit).each_delta do |delta|
            next if delta.status == :deleted
            if diffs_file_name && delta.new_file[:path] =~ diffs_file_name
              return {type: 'file_name', commit_id: commit.oid, file_path: delta.new_file[:path]}
            end  
               
            if diffs_file_size 
              blob = rugged.rev_parse(delta.new_file[:oid])
              if blob && blob.type == :blob && !data_binary?(blob.content) && blob.size > diffs_file_size
                return {type: 'file_size', commit_id: commit.oid, file_path: delta.new_file[:path]}
              end
            end  
          end
        end
        return {}
      end

      def refs_hash_rpc
        if @refs_hash_rpc.nil?
          @refs_hash_rpc = Hash.new { |h, k| h[k] = [] }

          rugged.references.each do |r|
            target_oid = r.target.try(:oid)
            if target_oid
              sha = rev_parse_target(target_oid).oid
              @refs_hash_rpc[sha] << Gitlab::Git::Ref.new(r.name, target_oid)
            end
          end
        end
        @refs_hash_rpc
      end

      def clean(options = {})
        strategies = [:remove_untracked]
        strategies.push(:force) if options[:f]
        strategies.push(:remove_ignored) if options[:x]

        # TODO: implement this method
        # this is not a method in rugged so use pop3 to do it temp temporarliy
        cmd = "git clean "
        cmd << "-f " if options[:f]
        cmd << "-x " if options[:x]
        cmd << "-d " if options[:d]
        out_put, status = popen([cmd], full_path)
        return status
      end


      ###add
      def diff_with_size(from, to, options = {}, *paths)
        limit, offset = options.delete(:limit).to_i, options.delete(:offset).to_i
        diff_proc = options.delete(:proc)

        diffs = []
        diff_size = 0

        rugged_diffs = rugged.diff(from, to, options, *paths)
        diff_proc.call(rugged_diffs) if diff_proc && diff_proc.is_a?(Proc)
        diff_size = rugged_diffs.size
        if diff_size > offset
          rugged_diffs.each_patch.each_with_index do |p, i|
            diffs << Gitlab::Git::Diff.new(p) if i>=offset
            break if (limit+offset)>0 && i>=offset+limit-1
          end
        end
        return diffs, diff_size
      end

      def format_patch_by_cmd(from, to)
        base_commit = rugged.merge_base(from, to)
        out_put, status = popen(["git format-patch  #{base_commit}...#{to} --stdout"], full_path)
      end

      def use_patch(patch_path)
        return false unless File.exists?(patch_path)

        out_put, status = popen(["git apply --check #{patch_path}"], full_path)
        return false unless status

        out_put, status = popen(["git am #{patch_path}"], full_path)
        #repo sync msg
        # ProjectSyncClient.push path, 'push' if status
        return status
      end

      def merge_conflicts?(source_ref, target_ref)
        merge_index = merge_index(source_ref, target_ref)
        merge_index.conflicts?
      end

      def merge_index(target_ref, source_ref)
        our_commit = rugged.rev_parse(target_ref)
        their_commit = rugged.rev_parse(source_ref)

        raise "Invalid merge target" if our_commit.nil?
        raise "Invalid merge source" if their_commit.nil?

        rugged.merge_commits(our_commit, their_commit)
      end

      def merge_index_with_commits(source_ref, target_ref)
        our_commit = rugged.rev_parse(target_ref)
        their_commit = rugged.rev_parse(source_ref)

        raise "Invalid merge target" if our_commit.nil?
        raise "Invalid merge source" if their_commit.nil?

        status = rugged.merge_commits(our_commit, their_commit), [our_commit, their_commit]
        #repo sync msg
        # ProjectSyncClient.push path, 'push' if status
        status 
      end

      def merge_commit(index, target_ref, options)
        tree = index.write_tree(rugged)
        actual_options = options.merge(
            tree: tree,
            update_ref: "refs/heads/#{target_ref}"
        )

        result = Rugged::Commit.create(rugged, actual_options)
        #repo sync msg
        # ProjectSyncClient.push path, 'push'
        result 
      end

      def diff(from, to, options = {}, *paths)
        paths.map!{|p| p.gsub("\\","\\"*4)}
        diff_patches(from, to, options, *paths).map do |p|
          Gitlab::Git::Diff.new(p)
        end
      end

      def archive_to_str(treeish = 'master', prefix = nil, format = nil)
        git_archive_cmd = %W(git --git-dir=#{full_path} archive)
        git_archive_cmd << "--prefix=#{prefix}" if prefix
        git_archive_cmd << "--format=#{format}" if format
        git_archive_cmd += %W(-- #{treeish})

        out_put, status = popen(git_archive_cmd, full_path)
      end

      # Return repo size in megabytes
      def size
        size = popen(%W(du -s), full_path).first.strip.to_i
        (size.to_f / 1024).round(2)
      end

      def search_files_rpc(query, ref = nil)
        greps = []
        ref ||= root_ref

        populated_index(ref).each do |entry|
          # Discard submodules
          next if submodule?(entry)

          content = rugged.lookup(entry[:oid]).content
          greps += build_greps(content, query, ref, entry[:path])
        end

        greps
      end

      def get_gitmodule(entry, content)
        results = {}

        current = ""
        content.split("\n").each do |txt|
          if txt.match(/^\s*\[/)
            break if current != ""

            name = txt.match(/(?<=").*(?=")/)[0]
            if name.to_s.split("/").last==entry[:name]
              current = name
              results[:basename] = entry[:name]
            else
              next
            end
          else
            next if results.empty?
            match_data = txt.match(/(\w+)\s*=\s*(.*)/)
            results[match_data[1].to_sym] = match_data[2]
          end
        end
        results[:id] = entry[:oid] unless results.empty?
        results
      end

      def config(key, value=nil)
        if value.nil?
          rugged.config[key.to_s]
        else
          rugged.config[key.to_s]=value
        end
      end

      def drb_name
        Marshal.dump([self.class.name, [path]])
      end

      def gc_hooks
        Gitlab::Git::CacheHost.delete_cache_host(path)
        rugged.close
      end

      def root_ref
        @root_ref ||= discover_default_branch
      end
      
      def create_branch(branch_name, commit_id, options={})
        if options.empty?
          result = popen(["git branch -f #{branch_name} #{commit_id}"], full_path)
        else
          branchCollection = Rugged::BranchCollection.new self.rugged
          result = branchCollection.create(branch_name,commit_id,options)
        end
        #repo sync msg
        # ProjectSyncClient.push path, 'push'
        Gitlab::Git::Branch.new(result.name, result.target.oid)
      end

      def delete_branch(branch)
        result = rugged_branches.delete(branch)
        #repo sync msg
        # ProjectSyncClient.push path, 'push'
        result 
      rescue Rugged::ReferenceError => e
        false
      end

      # if options is empty, create_tag with {} will raise TypeError
      #options  {message:"#{message}",tagger: {name:"#{user_name}",email:"#{user_email}",time:Time.now}}
      def create_tag(tag_name, commit_id, options={})
        tagCollection = Rugged::TagCollection.new self.rugged
        if options.empty?
          result = tagCollection.create(tag_name,commit_id)
        else
          result = tagCollection.create(tag_name,commit_id,options)
        end
        #repo sync msg
        # ProjectSyncClient.push path, 'push'
        result
      end
      
      def delete_tag(tag_name)
        tagCollection = Rugged::TagCollection.new self.rugged
        result = tagCollection.delete(tag_name)
        #repo sync msg
        # ProjectSyncClient.push path, 'push'
        result 
      end

      def reference_exist?(ref)
	      rugged.references.exist? ref
      end

      def create_reference(ref,commit_id)
	      git_references = Rugged::ReferenceCollection.new(self.rugged)
	      git_references.create(ref,commit_id,{force: true})
      end

      def delete_reference(ref)
      	git_references = Rugged::ReferenceCollection.new(self.rugged)
        git_references.delete(ref)
      end

      def update_reference(ref, newrev, options={})
      	rugged.references.update(ref, newrev, options)
      end

      def create_or_update_reference(ref, newrev, oldrev=nil)
        if !self.reference_exist? ref
          # Create a new Ref:`ref`, and it's old_id is 40 * '0'.
          self.create_reference(ref, newrev)
        else
          if oldrev.nil?
            # If Ref:`ref` is "refs/merges/NN/merge", we don't know it's old_id,
            # just overwrite it.
            self.update_reference(ref, newrev, force: true)
          else
            # Check old_id, before update Ref:`ref`.
            self.update_reference(ref, newrev, old_id: oldrev, force: true)
          end
        end
      end

      def remote_class
        self.class
      end

      def tree(treeish = nil, paths = [])
        paths = paths.is_a?(Array) ? paths : [paths]
        p = paths.length == 0 ? nil : paths.join(";")
        
        treeish ||= root_ref
        res = self.rev_parse_target(treeish) rescue nil
        return nil unless res

        if res.type == :tree
          return Gitlab::Git::Tree.new(
              id: res.oid,
              root_id: res.oid,
              path: p,
              repo_path: self.path,
          )
        elsif res.type == :commit
          tree = res.tree
          return Gitlab::Git::Tree.new(
              id: tree.oid,
              root_id: tree.oid,
              path: p,
              commit_id: res.oid,
              repo_path: self.path,
          )
        else
          return nil
        end
      end

      # Get a Tree class blob for the path
      def tree_blob(ref, path)
        ref ||= 'master'
        commit = self.commit ref
        tree = commit.tree_rpc
        Tree.content_by_path(self, tree.id, path, commit.id, tree.path)
      end


      # quick way to get a simple array of hashes of the entries
      # of a single tree or recursive tree listing from a given
      # sha or reference
      #   +treeish+ is the reference (default 'master')
      #   +options+ is a hash or options - currently only takes :recursive
      #
      # Examples
      #   repo.lstree('master', :recursive => true)
      #
      # Returns array of hashes - one per tree entry

      def lstree(treeish = 'master', options = {})
        tree = self.tree(treeish)
        Tree.tree_contents(self, tree.id)
      end

      def ls_blob_names(treeish = 'master', options = {})
        tree = self.tree(treeish)
        tree.all_blob_names(self)
      end

      # The Blob object for the given id
      #   +id+ is the SHA1 id of the blob
      #
      # Returns Gitlab::Git::Blob (unbaked)
      def blob(id, commit_sha=nil, path=nil)
        blob = self.lookup(id); blob_entry={}
        if commit_sha && path
          commit = self.lookup(commit_sha)
          unless commit
            root_tree = commit.tree
            blob_entry = Gitlab::Git::Blob.find_entry_by_path(self, root_tree.oid, path)
          end
        end
        if blob
          Gitlab::Git::Blob.new(
              id: blob.oid,
              name: blob_entry[:name],
              size: blob.size,
              data: blob.content,
              mode: blob_entry[:mode],
              path: path,
              commit_id: commit_sha,
          )
        end
      end

      def blob_by_commit_and_path(commit_sha, path)
        commit = self.lookup(commit_sha)
        if commit
          root_tree = commit.tree
          blob_entry = Gitlab::Git::Blob.find_entry_by_path(self, root_tree.oid, path)
          blob = self.lookup(blob_entry[:oid])
          if blob
            return Gitlab::Git::Blob.new(
              id: blob_entry[:oid],
              name: blob_entry[:name],
              size: blob.size,
              data: blob.content,
              mode: blob_entry[:mode],
              path: path,
              commit_id: commit_sha,
            )
          end
        end
        return nil
      end

      def blob_content_by_id(id)
        blob = self.lookup(id)
        if blob
          Gitlab::Git::Blob.new(
            id: blob.oid,
            size: blob.size,
            data: blob.content
          )
        else
          nil
        end
      end

      # An array of Commit objects representing the history of a given ref/commit
      #   +start+ is the branch/commit name (default 'master')
      #   +max_count+ is the maximum number of commits to return (default 10, use +false+ for all)
      #   +skip+ is the number of commits to skip (default 0)
      #
      # Returns Gitlab::Git::Commit[] (baked)
      def commits(start = 'master', max_count = 10, skip = 0)
        self.find_commits(options = {:ref => start, :max_count => max_count, :skip => skip})
      end

      # The Commit object for the specified id
      #   +id+ is the SHA1 identifier of the commit
      #
      # Returns Gitlab::Git::Commit (baked)
      def commit(id)
        Gitlab::Git::Commit.find(self, id)
      end

      def log(options)
        default_options = {
            limit: 10,
            offset: 0,
            path: nil,
            ref: root_ref,
            follow: false,
            skip_merges: false
        }

        options = default_options.merge(options)
        options[:limit] ||= 0
        options[:offset] ||= 0
        actual_ref = options[:ref] || root_ref
        begin
          sha = sha_from_ref(actual_ref)
        rescue Rugged::OdbError, Rugged::InvalidError, Rugged::ReferenceError
          # Return an empty array if the ref wasn't found
          return []
        end

        repo = options[:repo]

        cmd = %W(git --git-dir=#{full_path} log)
        cmd += %W(-n #{options[:limit].to_i})
        cmd += %W(--format=%H)
        cmd += %W(--skip=#{options[:offset].to_i})
        cmd += %W(--follow) if options[:follow]
        cmd += %W(--no-merges) if options[:skip_merges]
        cmd += [sha]
        cmd += %W(-- #{options[:path].gsub("\\","\\"*4)}) if options[:path]

        raw_output = IO.popen(cmd) {|io| io.read }

        log = raw_output.lines.map do |c|
          Gitlab::Git::Commit.decorate_rpc Rugged::Commit.new(rugged, c.strip), self.path
        end

        log.is_a?(Array) ? log : []
      end

      def rev_list(options)
        cmd = %W(git --git-dir=#{full_path} rev-list #{options[:ref]})
        cmd += %W(-- #{options[:path]}) if options[:path]
        raw_output = IO.popen(cmd) {|io| io.read }
        raw_output.split("\n")
      rescue
        []
      end

      # Archive Project to .tar.gz
      #
      # Already packed repo archives stored at
      # app_root/tmp/repositories/<project_name>.git/<project_name>-<ref>-<commit id>.tar.gz
      #
      def archive_repo(ref, storage_path, format = "tar.gz")
        ref ||= root_ref

        file_path = archive_file_path(ref, storage_path, format)
        return nil unless file_path

        return file_path if File.exist?(file_path)

        case format
          when "tar.bz2", "tbz", "tbz2", "tb2", "bz2"
            compress_cmd = %W(bzip2)
          when "tar"
            compress_cmd = %W(cat)
          when "zip"
            git_archive_format = "zip"
            compress_cmd = %W(cat)
          else
            # everything else should fall back to tar.gz
            compress_cmd = %W(gzip -n)
        end

        FileUtils.mkdir_p File.dirname(file_path)

        pid_file_path = archive_pid_file_path(ref, storage_path, format)
        return file_path if File.exist?(pid_file_path)

        File.open(pid_file_path, "w") do |file|
          file.puts Process.pid
        end

        # Create the archive in temp file, to avoid leaving a corrupt archive
        # to be downloaded by the next user if we get interrupted while
        # creating the archive.
        temp_file_path = "#{file_path}.#{Process.pid}-#{Time.now.to_i}"

        begin
          archive_to_file(ref, temp_file_path, git_archive_format, compress_cmd)
        rescue
          FileUtils.rm(temp_file_path)
          raise
        ensure
          FileUtils.rm(pid_file_path)
        end

        # move temp file to persisted location
        FileUtils.move(temp_file_path, file_path)

        file_path
      end

      def archive_name(ref)
        ref ||= root_ref
        commit = Gitlab::Git::Commit.find(self, ref)
        return nil unless commit

        project_name = self.name.sub(/\.git\z/, "")
        file_name = "#{project_name}-#{ref}-#{commit.id}"
      end

      def archive_file_path(ref, storage_path, format = "tar.gz")
        # Build file path
        name = archive_name(ref)
        return nil unless name

        extension =
            case format
              when "tar.bz2", "tbz", "tbz2", "tb2", "bz2"
                "tar.bz2"
              when "tar"
                "tar"
              when "zip"
                "zip"
              else
                # everything else should fall back to tar.gz
                "tar.gz"
            end

        file_name = "#{name}.#{extension}"
        File.join(storage_path, self.name, file_name)
      end

      def archive_pid_file_path(*args)
        "#{archive_file_path(*args)}.pid"
      end

      def disk_space
        output, status = popen(["du -sk"], full_path) 
        if status==0
          output.split(/\t/).first
        else
          0
        end
      end

      private

      def archive_to_file(treeish = 'master', filename = 'archive.tar.gz', format = nil, compress_cmd = %W(gzip -n))
        git_archive_cmd = %W(git --git-dir=#{full_path} archive)

        # Put files into a directory before archiving
        prefix = "#{archive_name(treeish)}/"
        git_archive_cmd << "--prefix=#{prefix}"

        # Format defaults to tar
        git_archive_cmd << "--format=#{format}" if format

        git_archive_cmd += %W(-- #{treeish})

        open(filename, 'w') do |file|
          # Create a pipe to act as the '|' in 'git archive ... | gzip'
          pipe_rd, pipe_wr = IO.pipe

          # Get the compression process ready to accept data from the read end
          # of the pipe
          compress_pid = spawn(*compress_cmd, in: pipe_rd, out: file)
          # Set the lowest priority for the compressing process
          popen(nice_process(compress_pid), full_path)
          # The read end belongs to the compression process now; we should
          # close our file descriptor for it.
          pipe_rd.close

          # Start 'git archive' and tell it to write into the write end of the
          # pipe.
          git_archive_pid = spawn(*git_archive_cmd, out: pipe_wr)
          # The write end belongs to 'git archive' now; close it.
          pipe_wr.close

          # When 'git archive' and the compression process are finished, we are
          # done.
          Process.waitpid(git_archive_pid)
          raise "#{git_archive_cmd.join(' ')} failed" unless $?.success?
          Process.waitpid(compress_pid)
          raise "#{compress_cmd.join(' ')} failed" unless $?.success?
        end
      end

      # Discovers the default branch based on the repository's available branches
      #
      # - If no branches are present, returns nil
      # - If one branch is present, returns its name
      # - If two or more branches are present, returns current HEAD or master or first branch
      def discover_default_branch
        now_head = Ref.extract_branch_name(rugged_head.name)
        return now_head if now_head.to_s != ""

        names = local_branch_names
        if names.length == 0
          nil
        elsif names.include?("master")
          "master"
        else
          names.first
        end
      end

      def local_branch_names
        output, status = popen(["git branch"], full_path)
        if status==0
          output.to_s.strip.split(/[\s*]+/)
        else
          []
        end
      end

      def rugged_head
        rugged.head
      rescue Rugged::ReferenceError
        nil
      end

      def rugged_branches

        return @rugged_branches unless @rugged_branches.nil?
        @rugged_branches = rugged.branches
      end

      def rugged_references
        return @rugged_references unless @rugged_references.nil?
        @rugged_references = rugged.references
      end

      def parse_ref_to_commit(reference)
        if reference.target.is_a?(Rugged::Commit)
          return reference.target
        else
          parse_ref_to_commit(reference.target)
        end
      end

      # Return an array of log commits, given an SHA hash and a hash of options.
      def build_log(sha, options)
        # Instantiate a Walker and add the SHA hash
        walker = Rugged::Walker.new(rugged)
        walker.push(sha)

        commits = []
        skipped = 0
        current_path = options[:path]
        current_path = nil if current_path == ''

        limit = options[:limit].to_i
        offset = options[:offset].to_i
        skip_merges = options[:skip_merges]

        walker.sorting(Rugged::SORT_DATE)
        walker.each do |c|
          break if limit > 0 && commits.length >= limit

          if skip_merges
            # Skip merge commits
            next if c.parents.length > 1
          end

          if !current_path ||
              commit_touches_path?(c, current_path, options[:follow], walker)

            # This is a commit we care about, unless we haven't skipped enough
            # yet
            skipped += 1
            commits.push(c) if skipped > offset
          end
        end

        walker.reset

        commits
      end

      def rugged_diff
        options ||= {}
        break_rewrites = options[:break_rewrites]
        actual_options = Diff.filter_diff_options(options.merge(paths: paths))
        options.delete(:proc)

        rugged.diff(from, to, actual_options)
      end
    end
  end
end
