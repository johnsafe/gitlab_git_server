require "spec_helper"

describe Gitlab::Git::Repository do
  include EncodingHelper
  let(:repository) { Gitlab::Git::Repository.new(TEST_REPO_PATH) }
  let(:merge_repo) { Gitlab::Git::MergeRepo.new(repository,'master','feature') }
  let(:patch_path) { File.join(SeedRepo::Repo::DEFAULT_PATCH_PATH,"a.patch") }

  describe "#diffs" do
    subject { merge_repo.diffs }
    it { merge_repo.diffs[:diffs].should be_kind_of Array }
  end

  describe "commits" do
    subject { merge_repo.commits }
    it { merge_repo.commits[:commits].should be_kind_of Array }
  end

  describe "#diffs_and_commits" do
    subject { merge_repo.diffs_and_commits }
    it { merge_repo.diffs[:diffs].should be_kind_of Array }
    it { merge_repo.commits[:commits].should be_kind_of Array }
  end

  describe "#compare" do
    subject { merge_repo.compare }
    it { should be_kind_of Gitlab::Git::Compare }
  end

  describe "#target_branch" do
    subject { merge_repo.target_branch }
    it { should == 'master' }
  end

  describe "#source_branch" do
    subject { merge_repo.source_branch }
    it { should == 'feature' }
  end

  describe "#head" do
    subject { merge_repo.head }
    it { should be_kind_of Gitlab::Git::Commit }
  end

  describe "#base" do
    subject { merge_repo.base }
    it { should be_kind_of Gitlab::Git::Commit }
  end


  describe "#same" do
    subject { merge_repo.same }
    it { should be_false }
  end

  describe "#merge_conflicts?" do
    subject { merge_repo.merge_conflicts? }
    it { should be_false }
  end

  describe "#merge!" do
    subject { merge_repo.merge!('example','example@163.com','test') }
    it { should be_true }
  end

  describe "#merge_index" do
    subject { merge_repo.merge_index }
    it { should be_kind_of Rugged::Index }
  end

  describe "#save_patch" do
    subject! { merge_repo.save_patch('a.patch') }
    it { should == 0 }
    it { File.exists?(patch_path).should be_true }
    after(:all) { FileUtils.rm_r(patch_path) }
  end

  RSpec.shared_examples "collections" do |repo_path, source_repo_path, source_branch, target_branch|
    describe "commits_and_diffs" do
      subject {Gitlab::Git::MergeRepo.commits_and_diffs(repo_path, target_branch, source_branch, source_repo_path)}
      it { should be_kind_of Hash}
      it { should include({timeout_diffs: false, diffs_size: 5, commits_size: 7})}
    end

    describe "cache" do
      subject {Gitlab::Git::MergeRepo.cache(repo_path, target_branch, source_branch, source_repo_path)}
      it { should be_kind_of Hash}
      it { should include({timeout_diffs: false, diffs_size: 5, commits_size: 7})}
    end

    describe "save_patch" do
      subject! {Gitlab::Git::MergeRepo.save_patch(repo_path, target_branch, source_branch, source_repo_path, {patch_name: "b.patch"})}
      it { should be_kind_of Array}
      it { File.exists?("#{Gitlab::Git::MergeRepo::DEFAULT_PATCH_PATH}b.patch").should be_true }
      after(:all) { FileUtils.rm_r("#{Gitlab::Git::MergeRepo::DEFAULT_PATCH_PATH}b.patch") }
    end

    describe "merge_conflict_files" do
      subject {Gitlab::Git::MergeRepo.merge_conflict_files(repo_path, target_branch, source_branch, source_repo_path)}
      it { should be_kind_of Array}
      its(:size) {should == 1}
      describe "automerge!" do
        subject {Gitlab::Git::MergeRepo.automerge!(repo_path, target_branch, source_branch, source_repo_path, {username: "liuhq002", useremail: "liuhq@csdn.net"})}
        it { should be_kind_of Array}
        it { should start_with(false)}
        # describe "merge_conflict_files" do
        #   subject {Gitlab::Git::MergeRepo.merge_conflict_files(repo, target_branch, source_branch, source_repo_path)}
        #   its(:size) { should == 1}
        #   describe "conflict_merge!" do
        #     subject {Gitlab::Git::MergeRepo.conflict_merge!(repo, target_branch, source_branch, source_repo_path, {username: "liuhq002", useremail: "liuhq@csdn.net", resolve_hash: {"LICENSE" => {type: 'edit', content: 'modify it'}}})}
        #     it { should be_true}
        #   end
        # end
      end
    end
  end

  RSpec.describe "same_repo" do
    #repo = Gitlab::Git::Repository.new(TEST_REPO_PATH)
    include_examples "collections", TEST_REPO_PATH, nil, "master", "test_merge_same"
  end

  RSpec.describe "diff_repo" do
    #repo = Gitlab::Git::Repository.new(TEST_REPO_PATH)
    include_examples "collections", TEST_REPO_PATH, MERGE_PATH, "master", "test_merge_diff"
  end

end
