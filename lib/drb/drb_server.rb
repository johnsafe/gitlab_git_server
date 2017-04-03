#encoding: utf-8
require 'digest/md5'
require 'drb'

module DRb
  class DRbTimeout < StandardError;end
  class DRbProcessError < StandardError;end
  class SocketTimeout < SocketError; end

  class DRbMessage
    HOSTNAME = Gitlab::Git::Settings.hostname
    private
    def make_proxy(obj, error=false) # :nodoc:
      if error
        DRbRemoteError.new(obj)
      else
        @drb_obj_uri ||= DRb.uri.sub("0.0.0.0", HOSTNAME)
        DRbObject.new(obj, @drb_obj_uri)
      end
    end
  end

  class DRbTCPSocket
    REQUEST_WAIT_TIMEOUT = Gitlab::Git::Settings.drb.request_wait_timeout
    alias :recv_request_without_timeout :recv_request
    #alias :send_reply_without_timeout :send_reply

    def recv_request
      select_timeout(:read, REQUEST_WAIT_TIMEOUT)
      recv_request_without_timeout
    end

    #def send_reply(succ, result)
    #  select_timeout(:write, timeout)
    #  @msg.send_reply_without_timeout(stream, succ, result)
    #end

    def select_timeout(type, timeout)
      if type == :read
        read_array = [stream]
      else
        write_array = [stream]
      end
   
      return true if IO.select(read_array, write_array, [stream], timeout)
      raise SocketTimeout, "Wait #{type} timeout!"
    end
  end

  class DRbServer
    HEAVY_METHOD_TIME = Gitlab::Git::Settings.heavy_method_time rescue 0.05

    class InvokeMethod
      TIME_OUT_TIME = 20

      alias :init_with_client_without_log :init_with_client

      def init_with_client
        result = init_with_client_without_log
        logger_string = "drb call:#{@obj.class},#{@msg_id}, args: #{@argv.inspect}"
        DRb::MyLogger.new_logger_id(Digest::MD5.hexdigest(Time.now.to_f.to_s + logger_string))

        $start_time = Time.now
        DRb::MyLogger.logger("#{logger_string}")
        result
      end

      def perform
        @result = nil
        @succ = false
        begin
          setup_message
        ensure
          yield if block_given?
        end

        if $SAFE < @safe_level
          info = Thread.current['DRb']
          if @block
            @result = Thread.new {
              Thread.current['DRb'] = info
              $SAFE = @safe_level
              perform_with_block
            }.value
          else
            @result = Thread.new {
              Thread.current['DRb'] = info
              $SAFE = @safe_level
              perform_without_block
            }.value
          end
        else
          if @block
            @result = perform_with_block
          else
            @result = perform_without_block
          end
        end
        @succ = true
        if @msg_id == :to_ary && @result.class == Array
          @result = DRbArray.new(@result)
        end
        return @succ, @result
      rescue SocketTimeout => e
        raise e
      rescue StandardError, ScriptError, Interrupt
        @result = $!
        return @succ, @result
      end

      def drb_timeout
        if @argv && @argv.last && @argv.last.is_a?(Hash) && @argv.last.has_key?(:drb_timeout)
          drb_timeout = @argv.pop[:drb_timeout]
          if drb_timeout.respond_to?(:to_f)
            return drb_timeout.to_f
          else
            return false
          end
        end
        return TIME_OUT_TIME
      end
    end

    def main_loop
      @pipe_readers ||= []
      client0 = @protocol.accept
      return nil if !client0

      # If health check will raise error here
      client_addr = client0.stream.peeraddr

      reader0, writer = IO.pipe
      DRb.mutex.synchronize do
        @pipe_readers << reader0
      end

      fork_process0 = fork do
        p "#{Time.now}: Connect open, pid: #{Process.pid} , addr: #{client_addr}" rescue nil

        at_exit do
          p "#{Time.now}: Connect close, pid: #{Process.pid} , addr: #{client_addr}" rescue nil

          if $!.respond_to?(:signm) && $!.signm == 'SIGQUIT'
            error = DRbTimeout.new("execution expired")
            error.set_backtrace([])
            client0.send_reply(false, error)
          end
        end

        # Close socket lisener 
        @protocol.close rescue nil

        # Close all reader pipes
        @pipe_readers.each do |reader|
          reader.close rescue nil
        end

        loop do
          begin
            succ = false
            invoke_method = InvokeMethod.new(self, client0)
            
            succ, result = invoke_method.perform do
              timeout = invoke_method.drb_timeout
              writer.puts timeout
            end

            cost_time  = Time.now - $start_time rescue 0
            client0.send_reply(succ, result)

            DRb::MyLogger.logger "success: #{succ}"
            if !succ
              result.backtrace.each do |x|
                DRb::MyLogger.logger x
              end
            end
            DRb::MyLogger.logger "[heavy method warning] #{cost_time}" if cost_time > HEAVY_METHOD_TIME

            if succ
              writer.puts "End"
            else
              # no need to send close, pipe will receve '' in read 
              break
            end
          rescue Errno::EPIPE => e
            p "#{Time.now}: process #{Process.pid} pipe error : #{e}"
            break
          rescue  => e
            p "#{Time.now}: process #{Process.pid} has error: #{$!}"
            client0.send_reply(false, $!) rescue nil
            break
          end
        end
      end

      # Close writer
      writer.close
      # Close client in main_loop
      client0

      Thread.start(client0, reader0, fork_process0) do |client, reader, fork_process|
        end_signal = :TERM
        begin
          @grp.add Thread.current
          Thread.current['DRb'] = { 'client' => client ,
                                    'server' => self }
          DRb.mutex.synchronize do
            client_uri = client.uri
            @exported_uri << client_uri unless @exported_uri.include?(client_uri)
          end

          thread_detach = Process.detach(fork_process)
          while thread_detach.alive?
            begin
              timeout = reader.gets.to_s
              timeout.chomp!

              if timeout =~ /^[0-9.]+$/
                Timeout.timeout(timeout.to_f, DRbTimeout) do
                  end_single =  reader.gets.to_s
                  raise DRbProcessError.new("end single error!") if end_single.chomp != "End"
                end
              elsif timeout == "false"
                end_single =  reader.gets.to_s
                raise DRbProcessError.new("end single error!") if end_single.chomp != "End"
              else
                # when connection close io will send a string "Close"
                raise DRbProcessError.new("Connection close")
              end
            rescue DRbTimeout => e
              p "#{Time.now}: process kill #{fork_process} time out: #{e.message}"
              error = DRbTimeout.new("execution expired")
              error.set_backtrace([])
              client.send_reply(false, error)
              end_signal = :QUIT
              break
            rescue => e
              p "#{Time.now}: process kill #{fork_process}: #{e.message}"
              break
            end
          end
        ensure
          begin
            reader.close rescue nil   
            DRb.mutex.synchronize do 
              @pipe_readers.delete(reader)
            end
            n = Process.kill(end_signal, fork_process) rescue nil
            if n.to_i == 1
              sleep 2
              Process.kill(:SIGKILL, fork_process) rescue nil
            end

          rescue => kill_excption
            p "kill_excption: #{kill_excption.message}"
          end
        end
      end
    rescue Errno::ENOTCONN
      # Health check rescue
      client0.close rescue nil
    rescue
      p "#{Time.now} main loop error: #{$!}"
      client0.close rescue nil
      writer.close rescue nil
      reader0.close rescue nil
      Process.kill(:TERM, fork_process0) rescue nil
    end
  end
end
