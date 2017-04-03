module SeedHelper
  GITHUB_URL = Gitlab::Git::Server::PRE_PATH + "../code_test/gitlab-git-test.git"

  def ensure_seeds
    path = File.join(Gitlab::Git::Server::PRE_PATH,'code_test')
    if File.exists?(path)
      FileUtils.rm_r(path)
    end

    FileUtils.mkdir_p(path)

    create_bare_seeds
    create_normal_seeds
    create_mutable_seeds
    create_bare_merge_seeds
  end

  def create_bare_seeds
    system(git_env, *%W(git clone --bare #{GITHUB_URL}), chdir: File.join(Gitlab::Git::Server::PRE_PATH,'code_test'))
  end

  def create_normal_seeds
    system(git_env, *%W(git clone #{File.join(Gitlab::Git::Server::PRE_PATH,TEST_REPO_PATH)} #{File.join(Gitlab::Git::Server::PRE_PATH,TEST_NORMAL_REPO_PATH)}))
  end

  def create_mutable_seeds
    system(git_env, *%W(git clone #{File.join(Gitlab::Git::Server::PRE_PATH,TEST_REPO_PATH)} #{File.join(Gitlab::Git::Server::PRE_PATH,TEST_MUTABLE_REPO_PATH)}))
    system(git_env, *%w(git branch -t feature origin/feature),
           chdir: File.join(Gitlab::Git::Server::PRE_PATH,TEST_MUTABLE_REPO_PATH))
    system(git_env, *%W(git remote add expendable #{GITHUB_URL}),
           chdir: File.join(Gitlab::Git::Server::PRE_PATH,TEST_MUTABLE_REPO_PATH))
  end

  def create_bare_merge_seeds
    system(git_env, *%W(git clone --bare #{GITHUB_URL} merge.git), chdir: File.join(Gitlab::Git::Server::PRE_PATH,'code_test'))
  end

  # Prevent developer git configurations from being persisted to test
  # repositories
  def git_env
    {'GIT_TEMPLATE_DIR' => ''}
  end
end
