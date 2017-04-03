module DiffsAnalysis
  def self.included(base)
    base.extend(DiffsAnalysis)
  end

  def analysis_diffs(diff, max_file_count=1000, max_line_count=10000)
    file_deltas = {added_count: 0, deleted_count: 0, modified_count: 0, over_flag: false}
    diff.each_delta do |delta|
      case delta.status
        when :added
          file_deltas[:added_count] += 1
        when :deleted
          file_deltas[:deleted_count] += 1
        when :modified
          file_deltas[:modified_count] += 1
      end

      if file_deltas[:added_count] > max_file_count || file_deltas[:deleted_count] > max_file_count || file_deltas[:modified_count] > max_file_count
        file_deltas[:over_flag] = true
        break
      end
    end

    line_deltas = {new_count: 0, old_count: 0, over_flag: false}
    diff.each_patch do |patch|
      new_count, old_count = patch.stat
      line_deltas[:new_count] += new_count
      line_deltas[:old_count] += old_count
      if line_deltas[:new_count] > max_line_count || line_deltas[:old_count] > max_line_count
        line_deltas[:over_flag] = true
        break
      end
    end

    return {file_deltas: file_deltas, line_deltas: line_deltas}
  end
end
