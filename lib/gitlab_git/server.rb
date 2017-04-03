#encoding: utf-8
require 'settingslogic'
module Gitlab
  module Git
    class Server
      PRE_PATH = Settings.repository.pre_path
      DEFAULT_PATCH_PATH = Settings.merge_repo.default_patch_path
      DRB_TIMEOUT = Gitlab::Git::Settings.drb.timeout
      def self.start(server_port)
        $drb_runing_process_id = [] 
        #$SAFE = 1 
        begin
          # include ::DrbGc 
          # #配置访问控制列表 
          # list = %w[ 
          #   deny all 
          #   allow 192.168.5.253 
          #   allow localhost 
          #   allow 192.168.8.* 
          # ] 
          # 
          # acl = ACL.new list, ACL::DENY_ALLOW 
          # #安装访问控制列表 
          # DRb.install_acl(acl) 
          puts "#{Time.now}: server start..."
          server = Gitlab::Git::DRbInterface.new
          DRb.install_id_conv(DRb::NameTimerIdConv.new(DRB_TIMEOUT))
          DRb.start_service "druby://0.0.0.0:#{server_port}", server
          DRb.thread.join
	rescue DRb::DRbConnError => e
	  puts "#{Time.now}: server DRbConnectionClosed #{$!}"
	  puts e.backtrace.join("\n")
	rescue => e
	  puts "#{Time.now}: Error #{$!}"
	  puts e.backtrace.join("\n")
	ensure
	  #if raise error in main process, kill fork process
	  p "#{Time.now}: main_process out kill fork_process"
	  p "all_process_id: #{$drb_runing_process_id}"
	  $drb_runing_process_id.each do |id|
	    Process.kill(:QUIT, id) rescue nil
	  end
	end
      end
    end
  end
end

