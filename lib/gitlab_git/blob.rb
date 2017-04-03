module Gitlab
  module Git
    class Blob
      DATA_SIZE_LIMIT = Gitlab::Git::Settings.blob.data_size_limit
      DATA_LINE_LIMIT = Gitlab::Git::Settings.blob.data_line_limit

      class << self
        def blame(repo, commit_id, path_with_name)
          g_blame = Gitlab::Git::Blame.new(repo, commit_id, path_with_name)
          r_blame = g_blame.blame
          blames = []
          entries = r_blame.entries
          lines = g_blame.lines
          (entries.last[:final_start_line_number]+entries.last[:lines_in_hunk]-lines.length).times do
            lines << ''
          end
          entries.each do |e|
            start = e[:final_start_line_number] - 1
            length = e[:lines_in_hunk]
            blames << [Gitlab::Git::Commit.find(repo, e[:final_commit_id]), g_blame.lines[start, length]]
          end
          blames
        end
      end

      def initialize(options)
        %w(id name path size mode commit_id).each do |key|
          self.send("#{key}=", options[key.to_sym])
        end

        options_data = options[:data].to_s
        @is_binary = if options[:binary]
                       options[:binary]
                     else
                       data_binary?(options_data) if options_data!=""
                     end

        if !@is_binary && !options[:full_data_flag] 
          new_data, index, word_size = [], 0, 0
          options_data.to_s.each_line do |line|
             word_size += line.size
             index += 1
             if word_size > DATA_SIZE_LIMIT || index > DATA_LINE_LIMIT
               @over_flow_flag = true
               break
             end
             new_data << line
          end
          
          self.data = new_data.join("")
        else
          self.data = options[:data].to_s
        end
      end

      def text?
        !binary?
      end

      def binary?
        @is_binary
      end

      def utf8_name
        encode! self.name
      end

      def utf8_data
        encode! self.data
      end

    end
  end
end
