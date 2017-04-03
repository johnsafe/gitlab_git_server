require "logger"

module DRb
  class MyLogger
    class << self
      def logger(content)
        server_log.error("[#{@call_logger_id}]  #{content}")
      end

      def new_logger_id(id)
        @call_logger_id = id
      end

      private
      def server_log
        return @server_log if @server_log
        log_file = File.join(File.dirname(__FILE__), '../../logs/server_call_log.log')
        @server_log = Logger.new(log_file)
      end
    end
  end
end

