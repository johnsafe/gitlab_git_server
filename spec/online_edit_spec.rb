require "spec_helper"

describe Gitlab::Git::OnlineEdit do
  include EncodingHelper

  let(:path) { 'b/a.txt' }
  let(:path1) { 'b/a1.txt' }
  let(:content) { 'Just do it!' }
  let(:content1) { 'I have done!' }

  before(:all) do
    branch_name = 'master'
    @online_edit = Gitlab::Git::OnlineEdit.new(TEST_REPO_PATH, branch_name) 
    @old_last_commit = @online_edit.send(:repo).last_commit.oid
    @online_edit.write_page(path, content)
    @online_edit.update_page(path, path1, content1)
    @new_commit_id = @online_edit.commit({author_name: 'test001', author_email: 'test001@csdn.net', message: "do a online edit"})
  end

  describe :write_page do

    it { @new_commit_id.should == @online_edit.send(:repo).last_commit.oid }
    it { @new_commit_id.should_not == @old_last_commit }

    describe "author" do
      subject { @online_edit.send(:repo).last_commit.author }
      it { should include(:name => "test001", :email => "test001@csdn.net") }
    end

    describe "content" do
      subject do
        repo = Gitlab::Git::Repository.new(TEST_REPO_PATH)
        Gitlab::Git::Blob.find(repo, 'master', path1).data
      end
      it { should == content1 }
    end
  end

end
