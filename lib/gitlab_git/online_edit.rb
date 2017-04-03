module Gitlab
  module Git
    class OnlineEdit
      include DRb::DRbUndumped
      include Gitlab::Git::ReflashOrderIndex
      attr_reader :repo_path, :ref, :pathname


      def initialize(repo_path, ref)
        @pathname = repo_path
        @repo_path = File.join(Settings.repository.pre_path, repo_path)
        @ref = ref
      end

      def write_page(file_path, data)
        entry = new_entry(file_path, data)
        index.add(entry)
      end

      #notice the data params must be utf8
      def update_page(old_file_path, new_file_path, data)
        old_entry = index[old_file_path]
        return false unless old_entry

        blob = repo.rev_parse(old_entry[:oid])
        data = data.to_s
        data.gsub!("\r\n", "\n") if check_next_line_type(blob.content) == :unix

        if old_file_path!=new_file_path
          delete_page(old_file_path) 
          old_entry[:path] = new_file_path
        end

        oid = repo.write(data, :blob)
        old_entry[:oid] = oid
        index.add(old_entry)
      end

      def delete_page(file_path) 
        return true unless index[file_path]
        index.remove(file_path) 
      end

      def commit(options)
        return false unless index_changed?
        commit_id = Rugged::Commit.create(repo, commit_options(options))
        @r_index =nil
        #repo sync msg
        # ProjectSyncClient.push @pathname, 'push'
        return commit_id
      end

      def method_missing(method, *args, &block)
        method_array = method.to_s.split('_')
        if method_array.include? 'remote'
          send (method_array-['remote']).join('_'), *args, &block
        else
          raise ArgumentError.new("no method called:#{method}")
        end
      end

      def revert!(commit_id, options)
        the_commit = find_commit(commit_id)
        return false unless the_commit

        c_options = { tree: index(the_commit).write_tree(repo),
                      update_ref: "refs/heads/#{ref}",
                      parents: parents
                    }.merge(author_options(options))
        Rugged::Commit.create(repo, c_options)
        #repo sync msg
        # ProjectSyncClient.push @pathname, 'push'
        return true
      end

      def drb_name
        Marshal.dump([self.class.name, [@pathname, @ref]])
      end

      private

      def repo
        @repo ||= Rugged::Repository.bare(repo_path)
      end

      def index(the_commit=nil)
        return @r_index if @r_index

        @r_index = repo.index

        the_commit = last_commit if !the_commit && last_commit
        @r_index.read_tree(the_commit.tree) if the_commit
        @old_entries = dump_entry(@r_index.entries)
        @r_index
      end

      def index_changed?
        return true if index.count != @old_entries.size

        @old_entries.each do |entry|
          new_entry = index.get(entry[:path])
          return true unless new_entry
          return true if new_entry[:oid] != entry[:oid]
        end
        return false
      end

      def dump_entry(entries)
        old_entries = []
        entries.each do |entry|
          old_entry = {}
          entry.each do |key, value|
            old_entry[key] = value
          end
          old_entries << old_entry
        end
        return old_entries
      end

      #{:path=>"About_Acknowledge.md", :oid=>"746df42ebc1116c94027abd5e246ae357c218510", :dev=>0, :ino=>0, :mode=>33188, :gid=>0, :uid=>0, :file_size=>0, :valid=>false, :stage=>0, :ctime=>1970-01-01 08:00:00 +0800, :mtime=>1970-01-01 08:00:00 +0800}
      def new_entry(path, data)
         now = Time.now
         oid = repo.write(data, :blob)
         {
         :path => path,
         :oid => oid,
         :mtime => now,
         :ctime => now,
         :file_size => 0,
         :dev => 0,
         :ino => 0,
         :mode => 33188,
         :uid => 0,
         :gid => 0,
         :stage => 0,
         }
      end

      def parents
        last_commit ? [last_commit.oid] : []
      end

      def last_commit
        find_commit(ref)
      end

      def find_commit(commit_id)
        obj = repo.rev_parse(commit_id)
        obj = obj.target while obj.is_a?(Rugged::Tag::Annotation)
        obj
      rescue Rugged::ReferenceError
        nil
      end

      def commit_options(option)
        options = author_options(option)
        { tree: index.write_tree(repo),
          update_ref: "refs/heads/#{ref}",
          parents: parents
        }.merge(options)
      end

      def author_options(option)
        author_email, author_name, message = option[:author_email], option[:author_name], option[:message]
        author = {:email => author_email.to_s, :time => Time.now, :name => author_name.to_s}
        {:author => author, :message => message.to_s, :committer => author}
      end


      def check_next_line_type(data)
        data = data.to_s[0, 1000]
        return :unkown if data=="" || data_binary?(data)

        pre_char, find_flag = nil, false
        data.chars.each do |char|
          if char == "\n"
             find_flag = true
             break
          end
          pre_char = char 
        end
        return :unkown if find_flag==false

        pre_char == "\r" ? :doc : :unix
      end
    end
  end
end
