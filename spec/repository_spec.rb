require "spec_helper"

describe Gitlab::Git::Repository do
  include EncodingHelper

  let(:repository) { Gitlab::Git::Repository.new(TEST_REPO_PATH) }
  describe "Respond to" do
    subject { repository }

    it { should respond_to(:raw) }
    it { should respond_to(:rugged) }
    it { should respond_to(:root_ref) }
    it { should respond_to(:tags) }
  end

  describe "#discover_default_branch" do
    let(:master) { 'master' }
    let(:feature) { 'feature' }
    let(:feature2) { 'feature2' }

    it "returns 'master' when master exists" do
      # repository.should_receive(:branch_names).at_least(:once).and_return([feature, master])
      repository.send(:discover_default_branch).should == 'master'
    end

=begin
    it "returns non-master when master exists but default branch is set to something else" do
      File.write(File.join(Gitlab::Git::Server::PRE_PATH, repository.path, 'HEAD'), 'ref: refs/heads/feature')
      repository.should_receive(:branch_names).at_least(:once).and_return([feature, master])
      repository.discover_default_branch.should == 'feature'
      File.write(File.join(Gitlab::Git::Server::PRE_PATH, repository.path, 'HEAD'), 'ref: refs/heads/master')
    end

    it "returns a non-master branch when only one exists" do
      repository.should_receive(:branch_names).at_least(:once).and_return([feature])
      repository.discover_default_branch.should == 'feature'
    end

    it "returns a non-master branch when more than one exists and master does not" do
      repository.should_receive(:branch_names).at_least(:once).and_return([feature, feature2])
      repository.discover_default_branch.should == 'feature'
    end

    it "returns nil when no branch exists" do
      repository.should_receive(:branch_names).at_least(:once).and_return([])
      repository.discover_default_branch.should be_nil
    end
=end
  end

  describe :branch_names do
    subject { repository.branch_names }

    it { should have(SeedRepo::Repo::BRANCHES.size).elements }
    it { should include("master") }
    it { should_not include("branch-from-space") }
  end

  describe :tags do
    subject { repository.tags }
    it { should be_kind_of Array }
    it { should have(SeedRepo::Repo::TAGS.size).elements }
  end

  describe :tag_names do
    subject { repository.tag_names }

    it { should be_kind_of Array }
    it { should have(SeedRepo::Repo::TAGS.size).elements }
    its(:last) { should == "v1.2.1" }
    it { should include("v1.0.0") }
    it { should_not include("v5.0.0") }
  end

  describe :commits_between_rpc do
    subject { repository.commits_between_rpc('master','feature') }
    it { should be_kind_of Array }
  end

  describe :format_patch do
    subject { repository.format_patch('master','feature') }
    it { should_not be_nil }
  end

  describe :find_commits do
    context 'with options' do
      subject do
        repository.find_commits(
            max_count: 50,
            ref: 'master'
        ).map { |c| c.id }
      end
      it { should include(SeedRepo::Commit::ID) }
      it { should include(SeedRepo::Commit::PARENT_ID) }
      it { should include(SeedRepo::FirstCommit::ID) }
    end
  end

  describe :clean do
    subject { repository.clean }
    it { should == 128 }
  end

  describe :diff_with_size do
    subject { repository.diff_with_size('master','feature').first.first }
    it { should be_kind_of Gitlab::Git::Diff }
  end

  describe :format_patch_by_cmd do
    subject { repository.format_patch_by_cmd('master','feature').last }
    it { should == 0 }
  end

  describe :merge_conflicts? do
    subject { repository.merge_conflicts?('master','feature') }
    it { should be_false }
  end

  describe :merge_index do
    subject { repository.merge_index('master','feature') }
    it { should be_kind_of Rugged::Index }
  end

  describe :merge_index_with_commits do
    subject { repository.merge_index_with_commits('master','feature') }
    it { should be_kind_of Array }
  end

  describe :config do
    subject { repository.config('user.name') }
    it { should be_kind_of String }
  end

  shared_examples 'archive check' do |extenstion|
    it { archive.should match(/tmp\/gitlab-git-test.git\/gitlab-git-test-master-#{SeedRepo::LastCommit::ID}/) }
    it { archive.should end_with extenstion }
    it { File.exists?(archive).should be_true }
    it { File.size?(archive).should_not be_nil }
  end

  describe :archive do
    let(:archive) { repository.archive_repo('master', '/tmp') }
    after { FileUtils.rm_r(archive) }

    it_should_behave_like 'archive check', '.tar.gz'
  end

  describe :archive_zip do
    let(:archive) { repository.archive_repo('master', '/tmp', 'zip') }
    after { FileUtils.rm_r(archive) }

    it_should_behave_like 'archive check', '.zip'
  end

  describe :archive_bz2 do
    let(:archive) { repository.archive_repo('master', '/tmp', 'tbz2') }
    after { FileUtils.rm_r(archive) }

    it_should_behave_like 'archive check', '.tar.bz2'
  end

  describe :archive_fallback do
    let(:archive) { repository.archive_repo('master', '/tmp', 'madeup') }
    after { FileUtils.rm_r(archive) }

    it_should_behave_like 'archive check', '.tar.gz'
  end

  describe :size do
    subject { repository.size }

    it { should < 2 }
  end

  describe :has_commits? do
    it { repository.has_commits?.should be_true }
  end

  describe :empty? do
    it { repository.empty?.should be_false }
  end

  describe :bare? do
    it { repository.bare?.should be_true }
  end

  describe :heads do
    let(:heads) { repository.heads }
    subject { heads }

    it { should be_kind_of Array }
    its(:size) { should eq(SeedRepo::Repo::BRANCHES.size) }

    context :head do
      subject { heads.first }

      its(:name) { should == "feature" }

      context :commit do
        subject { heads.first.target }

        it { should == "0b4bc9a49b562e85de7cc9e834518ea6828729b9" }
      end
    end
  end

  describe :ref_names do
    let(:ref_names) { repository.ref_names }
    subject { ref_names }

    it { should be_kind_of Array }
    its(:first) { should == 'feature' }
    its(:last) { should == 'v1.2.1' }
  end

  context :submodules do
    let(:repository) { Gitlab::Git::Repository.new(TEST_REPO_PATH) }

    context 'where repo has submodules' do
      let(:submodules) { repository.submodules('master') }
      let(:submodule) { submodules.first }

      it { submodules.should be_kind_of Hash }
      it { submodules.empty?.should be_false }

      it 'should have valid data' do
        submodule.should == [
            "six", {
                     "id"=>"409f37c4f05865e4fb208c771485f211a22c4c2d",
                     "path"=>"six",
                     "url"=>"git://github.com/randx/six.git"
                 }
        ]
      end

      it 'should handle nested submodules correctly' do
        nested = submodules['nested/six']
        expect(nested['path']).to eq('nested/six')
        expect(nested['url']).to eq('git://github.com/randx/six.git')
        expect(nested['id']).to eq('24fb71c79fcabc63dfd8832b12ee3bf2bf06b196')
      end

      it 'should handle deeply nested submodules correctly' do
        nested = submodules['deeper/nested/six']
        expect(nested['path']).to eq('deeper/nested/six')
        expect(nested['url']).to eq('git://github.com/randx/six.git')
        expect(nested['id']).to eq('24fb71c79fcabc63dfd8832b12ee3bf2bf06b196')
      end

      it 'should not have an entry for an invalid submodule' do
        expect(submodules).not_to have_key('invalid/path')
      end

      it 'should not have an entry for an uncommited submodule dir' do
        submodules = repository.submodules('fix-existing-submodule-dir')
        expect(submodules).not_to have_key('submodule-existing-dir')
      end

      it 'should handle tags correctly' do
        submodules = repository.submodules('v1.2.1')
        submodule.should == [
            "six", {
                     "id"=>"409f37c4f05865e4fb208c771485f211a22c4c2d",
                     "path"=>"six",
                     "url"=>"git://github.com/randx/six.git"
                 }
        ]
      end
    end

    context 'where repo doesn\'t have submodules' do
      let(:submodules) { repository.submodules('6d39438') }
      it 'should return an empty hash' do
        expect(submodules).to be_empty
      end
    end
  end

  describe :commit_count do
    it { repository.commit_count("master").should == 21 }
    it { repository.commit_count("feature").should == 9 }
  end

  describe :archive_repo do
    it { repository.archive_repo('master', '/tmp').should == "/tmp/gitlab-git-test.git/gitlab-git-test-master-#{SeedRepo::LastCommit::ID}.tar.gz" }
  end

  describe "#remote_names" do
    let(:remotes) { repository.remote_names }

    it "should have one entry: 'origin'" do
      expect(remotes).to have(1).items
      expect(remotes.first).to eq("origin")
    end
  end

  describe "#refs_hash" do
    let(:refs) { repository.refs_hash }

    it "should have as many entries as branches and tags" do
      expected_refs = SeedRepo::Repo::BRANCHES + SeedRepo::Repo::TAGS
      expect(refs.size).to have_at_least(1).items
      expect(refs.size).to have_at_most(expected_refs.size).items
    end
  end

  describe "#log" do
    commit_with_old_name = nil
    commit_with_new_name = nil
    rename_commit = nil

    before(:all) do
      # Add new commits so that there's a renamed file in the commit history
      repo = Gitlab::Git::Repository.new(TEST_REPO_PATH).rugged

      commit_with_old_name = new_commit_edit_old_file(repo)
      rename_commit = new_commit_move_file(repo)
      commit_with_new_name = new_commit_edit_new_file(repo)
    end

    context "where 'follow' == true" do
      options = { ref: "master", follow: true }

      context "and 'path' is a directory" do
        let(:log_commits) do
          repository.log(options.merge(path: "encoding"))
        end

        it "should not follow renames" do
          expect(log_commits.map(&:id)).to include(commit_with_new_name)
          expect(log_commits.map(&:id)).to include(rename_commit)
          expect(log_commits.map(&:id)).not_to include(commit_with_old_name)
        end
      end

      context "and 'path' is a file that matches the new filename" do
        let(:log_commits) do
          repository.log(options.merge(path: "encoding/CHANGELOG"))
        end

        it "should follow renames" do
          expect(log_commits.map(&:id)).to include(commit_with_new_name)
          expect(log_commits.map(&:id)).to include(rename_commit)
          expect(log_commits.map(&:id)).to include(commit_with_old_name)
        end
      end

      context "and 'path' is a file that matches the old filename" do
        let(:log_commits) do
          repository.log(options.merge(path: "CHANGELOG"))
        end

        it "should not follow renames" do
          expect(log_commits.map(&:id)).to include(commit_with_old_name)
          expect(log_commits.map(&:id)).to include(rename_commit)
          expect(log_commits.map(&:id)).not_to include(commit_with_new_name)
        end
      end

      context "unknown ref" do
        let(:log_commits) { repository.log(options.merge(ref: 'unknown')) }

        it "should return empty" do
          expect(log_commits.map(&:id)).to eq([])
        end
      end
    end

    context "where 'follow' == false" do
      options = { follow: false }

      context "and 'path' is a directory" do
        let(:log_commits) do
          repository.log(options.merge(path: "encoding"))
        end

        it "should not follow renames" do
          expect(log_commits.map(&:id)).to include(commit_with_new_name)
          expect(log_commits.map(&:id)).to include(rename_commit)
          expect(log_commits.map(&:id)).not_to include(commit_with_old_name)
        end
      end

      context "and 'path' is a file that matches the new filename" do
        let(:log_commits) do
          repository.log(options.merge(path: "encoding/CHANGELOG"))
        end

        it "should not follow renames" do
          expect(log_commits.map(&:id)).to include(commit_with_new_name)
          expect(log_commits.map(&:id)).to include(rename_commit)
          expect(log_commits.map(&:id)).not_to include(commit_with_old_name)
        end
      end

      context "and 'path' is a file that matches the old filename" do
        let(:log_commits) do
          repository.log(options.merge(path: "CHANGELOG"))
        end

        it "should not follow renames" do
          expect(log_commits.map(&:id)).to include(commit_with_old_name)
          expect(log_commits.map(&:id)).to include(rename_commit)
          expect(log_commits.map(&:id)).not_to include(commit_with_new_name)
        end
      end

      context "and 'path' includes a directory that used to be a file" do
        let(:log_commits) do
          repository.log(options.merge(ref: "refs/heads/fix-blob-path", path: "files/testdir/file.txt"))
        end

        it "should return a list of commits" do
          expect(log_commits.size).to eq(1)
        end
      end
    end

    after(:all) do
      # Erase our commits so other tests get the original repo
      repo = Gitlab::Git::Repository.new(TEST_REPO_PATH).rugged
      repo.references.update("refs/heads/master", SeedRepo::LastCommit::ID)
    end
  end

  describe "branch_names_contains" do
    subject { repository.branch_names_contains(SeedRepo::LastCommit::ID) }

    it { should include('master') }
    it { should_not include('feature') }
    it { should_not include('fix') }
  end

  describe '#branches with deleted branch' do
    # before(:each) do
    #   ref = double()
    #   ref.stub(:name) { 'bad-branch' }
    #   ref.stub(:target) { raise Rugged::ReferenceError }
    #   repository.rugged.stub(:branches) { [ref] }
    # end

    it 'should have as many as branches' do
      expect(repository.branches).to have(SeedRepo::Repo::BRANCHES.size).items
    end
  end

  describe :tree do
    let(:repo_tree) { repository.tree('master','files/html/500.html') }
    it 'should be kind of tree' do
      expect(repo_tree).to be_kind_of Gitlab::Git::Tree
    end
    it ' tree.path should be files/html/500.html' do
      expect(repo_tree.path).to eq('files/html/500.html')
    end
  end

  describe :ls_blob_names do
    subject { repository.ls_blob_names }
    it { should be_kind_of Array }
    it { should include '500.html' }
  end

  describe :blob do
    subject { repository.blob('998707b421c89bd9a3063333f9f728ef3e43d101','master','VERSION') }
    it { should be_kind_of Gitlab::Git::Blob }
  end

  describe :commits do
    subject { repository.commits }
    it { should be_kind_of Array }
  end

  describe :commit do
    subject { repository.commit('732401c65e924df81435deb12891ef570167d2e2') }
    it { should be_kind_of Gitlab::Git::Commit }
  end

  describe :repo_exists? do
    it { repository.repo_exists?.should be_true }
  end

  describe :rugged_head do
    subject { repository.send(:rugged_head) }
    it { should be_kind_of Rugged::Reference }
  end

  describe :rev_parse_target do
    subject { repository.rev_parse_target('master') }
    it { should be_kind_of Rugged::Commit }
  end

  describe :branches_contains do
    subject { repository.branches_contains('master').first }
    it { should be_kind_of Rugged::Branch }
  end

  describe :commits_since do
    subject { repository.commits_since(Date.new(2014,2,3)) }
    it { should be_kind_of Array }
  end

  describe :lstree do
    subject { repository.lstree('master') }
    it { should be_kind_of Array }
  end
end
