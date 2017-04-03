module Gitlab
  module Git
    class Blame
      include DRb::DRbUndumped
      attr_accessor :repo, :blame, :blob

      def self.blame_array(repo, sha, path)
        result = []
        begin
          blame = self.new(repo, sha, path)
          blame.each{|c, l, n| result << [c, l, n]}
        rescue => e
        end
        return result
      end


      def initialize(repository, sha, path)
        @repo = repository.rugged
        @blame = Rugged::Blame.new(@repo, path, {newest_commit: sha})
        @blob = @repo.blob_at(sha, path)
        @lines = @blob.content.split("\n")
      end

      def each
        @blame.each do |blame|
          from = blame[:final_start_line_number] - 1
          commit = @repo.lookup(blame[:final_commit_id])

          repo_path = @repo.path.sub(Gitlab::Git::Server::PRE_PATH, '')
          yield(Gitlab::Git::Commit.new(commit, repo_path),
              @lines[from, blame[:lines_in_hunk]] || [],
              blame[:final_start_line_number])
        end
      end
    end
  end
end
