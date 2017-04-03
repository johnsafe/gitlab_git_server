# Seed repo:
# 66028349a123e695b589e09a36634d976edcc5e8 Merge branch 'add-comments-to-gitmodules' into 'master'
# de5714f34c4e34f1d50b9a61a2e6c9132fe2b5fd Add comments to the end of .gitmodules to test parsing
# fa1b1e6c004a68b7d8763b86455da9e6b23e36d6 Merge branch 'add-files' into 'master'
# eb49186cfa5c4338011f5f590fac11bd66c5c631 Add submodules nested deeper than the root
# 18d9c205d0d22fdf62bc2f899443b83aafbf941f Add executables and links files
# 5937ac0a7beb003549fc5fd26fc247adbce4a52e Add submodule from gitlab.com
# 570e7b2abdd848b95f2f578043fc23bd6f6fd24d Change some files
# 6f6d7e7ed97bb5f0054f2b1df789b39ca89b6ff9 More submodules
# d14d6c0abdd253381df51a723d58691b2ee1ab08 Remove ds_store files
# c1acaa58bbcbc3eafe538cb8274ba387047b69f8 Ignore DS files
# ae73cb07c9eeaf35924a10f713b364d32b2dd34f Binary file added
# 874797c3a73b60d2187ed6e2fcabd289ff75171e Ruby files modified
# 2f63565e7aac07bcdadb654e253078b727143ec4 Modified image
# 33f3729a45c02fc67d00adb1b8bca394b0e761d9 Image added
# 913c66a37b4a45b9769037c55c2d238bd0942d2e Files, encoding and much more
# cfe32cf61b73a0d5e9f13e774abde7ff789b1660 Add submodule
# 6d394385cf567f80a8fd85055db1ab4c5295806f Added contributing guide
# 1a0b36b3cdad1d2ee32457c102a8c0b7056fa863 Initial commit
#
module SeedRepo
  module Commit
    ID = "570e7b2abdd848b95f2f578043fc23bd6f6fd24d"
    PARENT_ID = "6f6d7e7ed97bb5f0054f2b1df789b39ca89b6ff9"
    MESSAGE = "Change some files"
    AUTHOR_FULL_NAME = "Dmitriy Zaporozhets"

    FILES = ["files/ruby/popen.rb", "files/ruby/regex.rb"]
    FILES_COUNT = 2

    C_FILE_PATH = "files/ruby"
    C_FILES = ["popen.rb", "regex.rb", "version_info.rb"]

    BLOB_FILE = %{%h3= @key.title\n%hr\n%pre= @key.key\n.actions\n  = link_to 'Remove', @key, :confirm => 'Are you sure?', :method => :delete, :class => \"btn danger delete-key\"\n\n\n}
    BLOB_FILE_PATH = "app/views/keys/show.html.haml"
  end
end
