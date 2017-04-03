module Gitlab
  module Git
    module ReflashOrderIndex
      include EncodingHelper

      def reflash_order_and_index
        new_file_list_arr = new_file_list
        content_order = new_order_content(new_file_list_arr)
        content_index = new_index_content(new_file_list_arr)

        write_page("index_tree/order.md", content_order)
        write_page("index_tree/index.md", content_index)
      end

      def new_file_list
        order_file_list = get_file_from_orderfile
        repo_file_list = get_file_from_repo

        delete_file = order_file_list - repo_file_list
        add_file = repo_file_list - order_file_list
        order_file_list - delete_file + add_file - ["index_tree/order.md", "index_tree/index.md"]
      end

      def get_head_arr
        entry = index["index_tree/index.md"]
        return [] unless entry

        blob = repo.rev_parse(entry[:oid])
        content = encode!(blob.content)
        get_headers_arr_in_content(content, 3)
      end

      private

      def new_order_content(new_order_file_list)
        data_text = ""
        new_order_file_list.each do |file_path|
          data_text << "\#\#[#{file_path}](#{file_path})\r\n"
        end
        return data_text
      end

      def get_file_from_orderfile
        entry = index["index_tree/order.md"]
        return [] unless entry

        blob = repo.rev_parse(entry[:oid])
        content = encode!(blob.content)
        content.split(/\r?\n/).collect{|line| line.sub!(/^\#\#\[.*?\]\((.*?)\)$/, '\1') }.compact
      rescue
        []
      end

      def get_file_from_repo
        index.collect{|entry| encode!(entry[:path])}.sort
      end


      def new_index_content(new_file_list)
        headers = []
        new_file_list.each do |file_path|
          entry = index[file_path]
          next unless entry
          blob = repo.rev_parse(entry[:oid]) rescue nil
          next unless blob && blob.type == :blob && !data_binary?(blob.content)

          content = encode!(blob.content)
          headers += get_headers_arr_in_content(content, 3)
          headers << add_file_name_to_index(file_path)
        end
        generate_tree_num_and_links(headers).join("\n")
      end


      def get_headers_arr_in_content(content, n=6)
        headers = []

        lines = content.to_s.split(/\r?\n/)
        lines = remvoe_blocks(lines)

        lines.each_with_index do |line, i|
          headers << line if line =~ /^\#{1,#{n}}[^\#]+/
          headers << "##{lines[i-1]}" if line =~ /^=+$/ && i > 0
          headers << "###{lines[i-1]}" if line =~ /^-+$/ && i > 0
        end
        return headers
      end

      def add_file_name_to_index(file_path)
        file_arr = file_path.split('/')
        file_name = file_arr.pop

        return "file: [#{file_name}](#{file_path})"
      end

      def remvoe_blocks(lines)
        block_lines = []
        block_item = []
        lines.each_with_index do |line, i|
          if block_item.empty? && line =~ /^\`{3}.*/
            block_item[0] = i
          elsif !block_item.empty? && line =~ /^\`{3}/
            block_item[1] = i
            block_lines << block_item
            block_item = []
          end
        end

        block_lines.reverse.each do |block_item|
          block_item[1].downto(block_item[0]) {|arr_index| lines.delete_at(arr_index)}
        end
        return lines
      end

      def generate_tree_num_and_links(heads)
        heads_result = []
        num_arr = [0, 0, 0, 0, 0, 0]
        array_nums = []

        heads.each do |head|
          head.to_s.sub!(/#*$/,'')
          if  head =~ /^(#+)(.*)/
            dol, word = $1, $2

            num_arr[dol.size-1] = num_arr[dol.size-1] + 1
            num_arr[dol.size..-1] = [0]*(num_arr.size - dol.size)

            length = num_arr.size
            num_arr.reverse.each  do |i|
              if i < 1
                length = length - 1
              else
                break
              end
            end
            show_arr = num_arr[0, length]

            heads_result << "#{dol}#{show_arr.join('.')} [#{word}]"
            array_nums << heads_result.size - 1
          elsif head =~ /\]\((.*)\)/
            # add file_link with tags
            file_link = $1
            array_nums.each_with_index{|num, index| heads_result[num] << "(#{file_link}#anchor_#{index})"}
            array_nums = []

            heads_result << head
          end
        end
        return heads_result
      end
    end
  end
end
