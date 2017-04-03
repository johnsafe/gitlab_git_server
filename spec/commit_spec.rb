require "spec_helper"

describe Gitlab::Git::Commit do
  let(:repository) { Gitlab::Git::Repository.new(TEST_REPO_PATH) }
  let(:commit) { Gitlab::Git::Commit.find(repository, SeedRepo::Commit::ID) }
  let(:rugged_commit) do
    repository.rugged.lookup(SeedRepo::Commit::ID)
  end

  describe "Commit info" do
    before do
      repo = Gitlab::Git::Repository.new(TEST_REPO_PATH).rugged

      @committer = {
        email: 'mike@smith.com',
        name: "Mike Smith",
        time: Time.now
      }

      @author = {
        email: 'john@smith.com',
        name: "John Smith",
        time: Time.now
      }

      @parents = [repo.head.target]
      @gitlab_parents = @parents.map { |c| Gitlab::Git::Commit.decorate_rpc(c, TEST_REPO_PATH) }
      @tree = @parents.first.tree

      sha = Rugged::Commit.create(
        repo,
        author: @author,
        committer: @committer,
        tree: @tree,
        parents: @parents,
        message: "Refactoring specs",
        update_ref: "HEAD"
      )

      @raw_commit = repo.lookup(sha)
      @commit = Gitlab::Git::Commit.new(@raw_commit,TEST_REPO_PATH)
    end

    it { @commit.short_id.should == @raw_commit.oid[0..10] }
    it { @commit.id.should == @raw_commit.oid }
    it { @commit.sha.should == @raw_commit.oid }
    it { @commit.safe_message.should == @raw_commit.message }
    it { @commit.created_at.should == @raw_commit.author[:time] }
    it { @commit.date.should == @raw_commit.committer[:time] }
    it { @commit.author_email.should == @author[:email] }
    it { @commit.author_name.should == @author[:name] }
    it { @commit.committer_name.should == @committer[:name] }
    it { @commit.committer_email.should == @committer[:email] }
    it { @commit.different_committer?.should be_true }
    it { @commit.parents_rpc(@raw_commit).should_not be_nil }
    it { @commit.parent_id.should == @parents.first.oid }
    it { @commit.no_commit_message.should == "--no commit message" }
    # it { @commit.tree.should == @tree }
    it { @commit.tree_rpc.should be_kind_of Gitlab::Git::Tree }

    after do
      # Erase the new commit so other tests get the original repo
      repo = Gitlab::Git::Repository.new(TEST_REPO_PATH).rugged
      repo.references.update("refs/heads/master", SeedRepo::LastCommit::ID)
    end
  end

  context 'Class methods' do

    describe :remote_ref_names do
      it "should return a kind of Array" do
        commit.remote_ref_names.should be_kind_of Array
      end
    end

    describe :utf8_message do
      it "should return message" do
        commit.utf8_message.should be_kind_of String
      end
    end

    describe :committer do
      it "should return author" do
        commit.committer[:name].should == 'Dmitriy Zaporozhets'
      end
    end

    describe :rugged_tree do
      it "should return author" do
        commit.rugged_tree.keys.should include('README.md')
      end
    end

    describe :find do
      it "should return first head commit if without params" do
        Gitlab::Git::Commit.last(repository).id.should ==
          repository.raw.head.target.oid
      end

      it "should return valid commit" do
        Gitlab::Git::Commit.find(repository, SeedRepo::Commit::ID).should be_valid_commit
      end

      it "should return valid commit for tag" do
        Gitlab::Git::Commit.find(repository, 'v1.0.0').id.should == '6f6d7e7ed97bb5f0054f2b1df789b39ca89b6ff9'
      end

      it "should return nil for non-commit ids" do
        blob = Gitlab::Git::Blob.find(repository, SeedRepo::Commit::ID, "files/ruby/popen.rb")
        Gitlab::Git::Commit.find(repository, blob.id).should be_nil
      end

      it "should return nil for parent of non-commit object" do
        blob = Gitlab::Git::Blob.find(repository, SeedRepo::Commit::ID, "files/ruby/popen.rb")
        Gitlab::Git::Commit.find(repository, "#{blob.id}^").should be_nil
      end

      it "should return nil for nonexisting ids" do
        Gitlab::Git::Commit.find(repository, "+123_4532530XYZ").should be_nil
      end
    end

    describe :last_for_path do
      context 'no path' do
        subject { Gitlab::Git::Commit.last_for_path(repository, 'master') }

        its(:id) { should == SeedRepo::LastCommit::ID }
      end

      context 'path' do
        subject { Gitlab::Git::Commit.last_for_path(repository, 'master', 'files/ruby') }

        its(:id) { should == SeedRepo::Commit::ID }
      end

      context 'ref + path' do
        subject { Gitlab::Git::Commit.last_for_path(repository, SeedRepo::Commit::ID, 'encoding') }

        its(:id) { should == SeedRepo::BigCommit::ID }
      end
    end


    describe "where" do
      context 'ref is branch name' do
        subject do
          commits = Gitlab::Git::Commit.where(
            repo: repository,
            ref: 'master',
            path: 'files',
            limit: 3,
            offset: 1
          )

          commits.map { |c| c.id }
        end

        it { should have(3).elements }
        it { should include("874797c3a73b60d2187ed6e2fcabd289ff75171e") }
        it { should_not include("eb49186cfa5c4338011f5f590fac11bd66c5c631") }
      end

      context 'ref is commit id' do
        subject do
          commits = Gitlab::Git::Commit.where(
            repo: repository,
            ref: "874797c3a73b60d2187ed6e2fcabd289ff75171e",
            path: 'files',
            limit: 3,
            offset: 1
          )

          commits.map { |c| c.id }
        end

        it { should have(3).elements }
        it { should include("2f63565e7aac07bcdadb654e253078b727143ec4") }
        it { should_not include(SeedRepo::Commit::ID) }
      end

      context 'ref is tag' do
        subject do
          commits = Gitlab::Git::Commit.where(
            repo: repository,
            ref: 'v1.0.0',
            path: 'files',
            limit: 3,
            offset: 1
          )

          commits.map { |c| c.id }
        end

        it { should have(3).elements }
        it { should include("874797c3a73b60d2187ed6e2fcabd289ff75171e") }
        it { should_not include(SeedRepo::Commit::ID) }
      end
    end

    describe :between do
      subject do
        commits = Gitlab::Git::Commit.between_rpc(repository, SeedRepo::Commit::PARENT_ID, SeedRepo::Commit::ID)
        commits.map { |c| c.id }
      end

      it { should have(1).elements }
      it { should include(SeedRepo::Commit::ID) }
      it { should_not include(SeedRepo::FirstCommit::ID) }
    end

    describe :find_all do
      context 'max_count' do
        subject do
          commits = Gitlab::Git::Commit.find_all(
            repository,
            max_count: 50
          )

          commits.map { |c| c.id }
        end

        it { should have(29).elements }
        it { should include(SeedRepo::Commit::ID) }
        it { should include(SeedRepo::Commit::PARENT_ID) }
        it { should include(SeedRepo::FirstCommit::ID) }
      end

      context 'ref + max_count + skip' do
        subject do
          commits = Gitlab::Git::Commit.find_all(
            repository,
            ref: 'master',
            max_count: 50,
            skip: 1
          )

          commits.map { |c| c.id }
        end

        it { should have(20).elements }
        it { should include(SeedRepo::Commit::ID) }
        it { should include(SeedRepo::FirstCommit::ID) }
        it { should_not include(SeedRepo::LastCommit::ID) }
      end

      context 'contains feature + max_count' do
        subject do
          commits = Gitlab::Git::Commit.find_all(
            repository,
            contains: 'feature',
            max_count: 7
          )

          commits.map { |c| c.id }
        end

        it { should have(7).elements }

        it { should_not include(SeedRepo::Commit::PARENT_ID) }
        it { should_not include(SeedRepo::Commit::ID) }
        it { should include(SeedRepo::BigCommit::ID) }
      end
    end
  end

  describe :init_from_rugged do
    let(:gitlab_commit) { Gitlab::Git::Commit.new(rugged_commit,TEST_REPO_PATH) }
    subject { gitlab_commit }

    its(:id) { should == SeedRepo::Commit::ID }
  end

  describe :init_from_hash do
    let(:commit) { Gitlab::Git::Commit.new(add_repo_path_to_hash) }
    subject { commit }

    its(:id) { should == sample_commit_hash[:id]}
    its(:message) { should == sample_commit_hash[:message]}
  end

  describe :stats do
    subject { commit.stats }

    its(:additions) { should eq(11) }
    its(:deletions) { should eq(6) }
  end

  describe :to_diff do
    subject { commit.to_diff }

    it { should_not include "From #{SeedRepo::Commit::ID}" }
    it { should include 'diff --git a/files/ruby/popen.rb b/files/ruby/popen.rb'}
  end

  describe :has_zero_stats? do
    it { commit.has_zero_stats?.should == false }
  end

  describe :to_patch do
    subject { commit.to_patch }

    it { should include "From #{SeedRepo::Commit::ID}" }
    it { should include 'diff --git a/files/ruby/popen.rb b/files/ruby/popen.rb'}
  end

  describe :to_hash do
    let(:hash) { commit.to_hash }
    subject { hash }

    it { should be_kind_of Hash }
    its(:keys) { should =~ sample_commit_hash.keys }
  end

  # describe :diffs do
  #   subject { commit.diffs }
  #
  #   it { should be_kind_of Array }
  #   its(:size) { should eq(2) }
  #   its(:first) { should be_kind_of Gitlab::Git::Diff }
  # end

  describe :diffs_rpc do
    subject { commit.diffs_rpc }
    it { should be_kind_of Hash }
    its(:keys) { should == [:diffs_size, :diffs, :analysis_result] }
  end

  describe :ref_names do
    let(:commit) { Gitlab::Git::Commit.find(repository, 'master') }
    subject { commit.ref_names(repository) }

    it { should have(1).elements }
    it { should include("master") }
    it { should_not include("feature") }
  end

  def sample_commit_hash
    {
      author_email: "dmitriy.zaporozhets@gmail.com",
      author_name: "Dmitriy Zaporozhets",
      authored_date: "2012-02-27 20:51:12 +0200",
      committed_date: "2012-02-27 20:51:12 +0200",
      committer_email: "dmitriy.zaporozhets@gmail.com",
      committer_name: "Dmitriy Zaporozhets",
      id: SeedRepo::Commit::ID,
      message: "tree css fixes",
      parent_ids: ["874797c3a73b60d2187ed6e2fcabd289ff75171e"],
      tree_oid: nil
    }
  end
  def add_repo_path_to_hash
    sample_commit_hash.merge({repo_path: TEST_REPO_PATH})
  end
end
