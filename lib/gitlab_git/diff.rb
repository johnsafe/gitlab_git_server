# Gitlab::Git::Diff is a wrapper around native Rugged::Diff object
module Gitlab
  module Git
    class Diff
      DIFF_DATA_MAX_SIZE = 1024*100
      class << self

        def between_with_size(repo, head, base, options = {}, *paths)
          common_commit = repo.merge_base_commit(head, base)
          options ||= {}
          break_rewrites = options[:break_rewrites]
          actual_options = filter_diff_options(options)
          repo.diff_with_size(common_commit, head, actual_options, *paths)
        end

        #add :limit, :offset, :proc to allowed_options
        def filter_diff_options(options, default_options = {})
          allowed_options = [:max_size, :context_lines, :interhunk_lines,
                             :old_prefix, :new_prefix, :reverse, :force_text,
                             :ignore_whitespace, :ignore_whitespace_change,
                             :ignore_whitespace_eol, :ignore_submodules,
                             :patience, :include_ignored, :include_untracked,
                             :include_unmodified, :recurse_untracked_dirs,
                             :disable_pathspec_match, :deltas_are_icase,
                             :include_untracked_content, :skip_binary_check,
                             :include_typechange, :include_typechange_trees,
                             :ignore_filemode, :recurse_ignored_dirs, :paths, 
                             :limit, :offset, :proc]

          if default_options
            actual_defaults = default_options.dup
            actual_defaults.keep_if do |key|
              allowed_options.include?(key)
            end
          else
            actual_defaults = {}
          end

          if options
            filtered_opts = options.dup
            filtered_opts.keep_if do |key|
              allowed_options.include?(key)
            end
            filtered_opts = actual_defaults.merge(filtered_opts)
          else
            filtered_opts = actual_defaults
          end

          filtered_opts
        end
      end

      def initialize(raw_diff)
        raise "Nil as raw diff passed" unless raw_diff

        if raw_diff.is_a?(Hash)
          init_from_hash(raw_diff)
        elsif raw_diff.is_a?(Rugged::Patch) || raw_diff.is_a?(DRb::DRbObject)
          init_from_rugged(raw_diff)
        else
          raise "Invalid raw diff type: #{raw_diff.class}"
        end
        @diff = "Diff too large can`t show" if @diff.size > DIFF_DATA_MAX_SIZE
      end

      def strip_diff_headers(diff_text)
        return "Diff too big can`t show" if diff_text.size > DIFF_DATA_MAX_SIZE

        # Delete everything up to the first line that starts with '---' or
        # 'Binary'
        diff_text.sub!(/\A.*?^(---|Binary)/m, '\1')

        if diff_text.start_with?('---') or diff_text.start_with?('Binary')
          diff_text
        else
          # If the diff_text did not contain a line starting with '---' or
          # 'Binary', return the empty string. No idea why; we are just
          # preserving behavior from before the refactor.
          ''
        end
      end

      def utf8_diff
        encode! self.diff
      end

      def deleted_file?
        @deleted_file
      end

      def new_file?
        @new_file
      end

      def has_diff
        !diff.nil?
      end

    end
  end
end
