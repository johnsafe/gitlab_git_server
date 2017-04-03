#encoding: utf-8
# Libraries
require 'gitlab_git'
require "rchardet19"
require 'drb'
require 'redis'
require "redis-store"
require 'redis-namespace'
require 'digest/sha1'
require 'nokogiri'
require 'pygments.rb'
require 'github/markup'
require 'settingslogic'
require 'logger'
require 'sidekiq'

require_relative 'gitlab_git/settings.rb'
require_relative 'gitlab_git/workers/client_config'

require_relative "drb/my_logger"
require_relative "drb/name_time_id_coinv"
require_relative "drb/drb_server"  

require_relative 'gitlab_git/encoding_helper'
require_relative 'gitlab_git/redis_helper'

require_relative 'gitlab_git/cache_host'
require_relative 'gitlab_git/diffs_analysis'
require_relative 'gitlab_git/commit'
require_relative 'gitlab_git/commit_stats'
require_relative 'gitlab_git/repository'
require_relative 'gitlab_git/tree'
require_relative 'gitlab_git/submodule'
require_relative 'gitlab_git/blob'
require_relative 'gitlab_git/ref'
require_relative 'gitlab_git/blame'
require_relative 'gitlab_git/tag'
require_relative 'gitlab_git/diff'
require_relative 'gitlab_git/cmd'
require_relative 'gitlab_git/merge_repo'
require_relative 'gitlab_git/compare'
require_relative 'gitlab_git/reflash_order_index'
require_relative 'gitlab_git/online_edit'
require_relative 'gitlab_git/workers/fork_worker'

require_relative 'gitlab_git/drb_interface'
require_relative 'gitlab_git/server'

require_relative 'project_sync_client'

#
# require_relative 'gitlab_git/blob_snippet'
# require_relative 'gitlab_git/satellite'
# require_relative 'gitlab_git/wiki'
# require_relative 'gitlab_git/page'
# require_relative 'gitlab_git/markup'
# require_relative 'gitlab_git/wiki_file'
