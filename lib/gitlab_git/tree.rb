module Gitlab
  module Git
    class Tree
      extend EncodingHelper
      attr_accessor :id, :root_id, :name, :path, :type, :mode, :commit_id, :submodule_url, :repo_path
      class << self

        def where(repository, sha, path = nil)
          path = nil if path == '' || path == '/'

          commit = repository.lookup(sha)
          root_tree = commit.tree

          tree = if path
                   id = Tree.find_id_by_path(repository, root_tree.oid, path)
                   if id
                     repository.lookup(id)
                   else
                     []
                   end
                 else
                   root_tree
                 end

          tree.map do |entry|
            Tree.new(
                id: entry[:oid],
                root_id: root_tree.oid,
                name: entry[:name],
                type: entry[:type],
                mode: entry[:filemode],
                path: path ? File.join(path, entry[:name]) : entry[:name],
                commit_id: sha,
                repo_path: repository.path,
            )
          end
        end

        def find_id_by_path(repository, root_id, path)
          root_tree = repository.lookup(root_id)
          path_arr = path.split('/')

          entry = root_tree.find do |entry|
            entry[:name] == path_arr[0] && entry[:type] == :tree
          end

          return nil unless entry

          if path_arr.size > 1
            path_arr.shift
            find_id_by_path(repository, entry[:oid], path_arr.join('/'))
          else
            entry[:oid]
          end
        end



        #   # Find the named object in this tree's contents
        def content_by_path(repository, id, file_path, commit_id=nil, path=nil)
          entry = content_entry_by_path(repository, {oid: id}, file_path)
          entry.nil? ? nil : new_content_from_entry(repository, entry, path, commit_id)
        end


        def content_entry_by_path(repository, entry, file_path)
          if file_path =~ /\//
            file_path.split("/").inject(entry) { |acc, x| content_entry_by_path(repository, acc, x) } rescue nil
          else
            tree = repository.lookup(entry[:oid])
            tree[file_path]
          end
        end
        #
        def tree_contents(repository, id, path=nil, commit_id=nil, get_text_flag=true, need_text=true)
          tree = repository.lookup(id)
          tree.map do |entry|
            new_content_from_entry(repository, entry, path, commit_id, tree.oid, tree, get_text_flag, need_text)
          end
        end

        def new_content_from_entry(repo, entry, path, commit_id, root_id=nil, tree=nil, get_text_flag=true, need_text=true)
          if entry[:type] == :blob
            blob = repo.lookup(entry[:oid])
            is_binary = data_binary?(blob.text[0,256])
            init_hash = {
                id: blob.oid,
                name: entry[:name],
                size: blob.size,
                mode: entry[:mode],
                path: path.to_s!='' ? File.join(path, entry[:name]) : entry[:name],
                commit_id: commit_id,
                binary: is_binary
            }

            if need_text
              if is_binary
                binary_size_limit = Gitlab::Git::Settings.blob.binary_size_limit rescue 26214400
                init_hash[:data] = blob.size > binary_size_limit ? '' : blob.text
              else
                # if false we not need text but, for encoding we give 1024 words
                if get_text_flag
                  # this limit is not useful for all type of blob, move the limit to blob
                  init_hash[:data] = blob.text
                else
                  # if false we not need text but, for encoding we give 256 words
                  init_hash[:data] = blob.text[0, 256]
                end
              end
            else
              init_hash[:data] = ''
            end

            Gitlab::Git::Blob.new(init_hash)
          elsif entry[:type] == :tree
            Tree.new(
                id: entry[:oid],
                root_id: root_id,
                name: entry[:name],
                type: entry[:type],
                mode: entry[:filemode],
                path: path.to_s!='' ? File.join(path, entry[:name]) : entry[:name],
                commit_id: commit_id,
                repo_path: repo.path,
            )
          elsif entry[:type] == :commit
            submodule_hash = {basename: entry[:name], url: "", id: entry[:oid]}
            begin
              commit = repo.lookup(commit_id)
              entry_gm = commit.tree[".gitmodules"]
              blob_gm = repo.lookup(entry_gm[:oid])
              submodule_hash = repo.get_gitmodule(entry, blob_gm.text)
            rescue
            end
            Submodule.new(submodule_hash)
          end
        end

      end

      def initialize(options)
        %w(id root_id name path type mode commit_id submodule_url repo_path).each do |key|
          self.send("#{key}=", options[key.to_sym])
        end
      end

      def all_blob_names(repo)
        result = []
        if self.file?
          result << self.name
        else
          repo.lookup(self.id).each do |entry|
            if entry[:type] == :blob
              result << entry[:name]
            elsif entry[:type] == :tree
              sub_tree = Gitlab::Git::Tree.new({id: entry[:oid], root_id: entry[:oid], repo_path: repo_path, type:entry[:type]})
              result += sub_tree.all_blob_names(repo)
            end
          end
        end
        result
      end
    end
  end
end
