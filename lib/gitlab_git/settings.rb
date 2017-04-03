#encoding: utf-8
require 'settingslogic'
module Gitlab
  module Git
    class Settings < Settingslogic
      # if there is a config in code_be use it, when not use self's config
      config_path =  File.join(Dir.pwd.to_s, '..', 'config.yml')
      config_path =  File.join(Dir.pwd.to_s, 'config.yml') unless File.exist?(config_path)
      source config_path
    end
  end
end
