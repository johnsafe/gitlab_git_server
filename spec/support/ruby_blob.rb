#
# From SeedRepo::Commit::ID
#
module SeedRepo
  module RubyBlob
    ID = "7e3e39ebb9b2bf433b4ad17313770fbe4051649c"
    NAME = "popen.rb"
    CONTENT = <<-eos
require 'fileutils'
require 'open3'

module Popen
  extend self

  def popen(cmd, path=nil)
    unless cmd.is_a?(Array)
      raise RuntimeError, "System commands must be given as an array of strings"
    end

    path ||= Dir.pwd

    vars = {
      "PWD" => path
    }

    options = {
      chdir: path
    }

    unless File.directory?(path)
      FileUtils.mkdir_p(path)
    end

    @cmd_output = ""
    @cmd_status = 0

    Open3.popen3(vars, *cmd, options) do |stdin, stdout, stderr, wait_thr|
      @cmd_output << stdout.read
      @cmd_output << stderr.read
      @cmd_status = wait_thr.value.exitstatus
    end

    return @cmd_output, @cmd_status
  end
end
    eos
  end
end
