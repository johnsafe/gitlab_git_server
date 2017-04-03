require 'drb/drb'
require 'monitor'

module DRb
  # Timer id conversion keeps objects alive for a certain amount of time after
  # their last access.  The default time period is 600 seconds and can be
  # changed upon initialization.
  #
  # To use TimerIdConv:
  #
  #  DRb.install_id_conv TimerIdConv.new 60 # one minute

  class NameTimerIdConv < DRbIdConv
    class NameTimerHolder # :nodoc:
      DRB_NEW_OBJS = ["Gitlab::Git::Repository", "Gitlab::Git::OnlineEdit"]
 
      include MonitorMixin

      class InvalidIndexError < RuntimeError; end

      def initialize(timeout=600)
        super()
        @sentinel = Object.new
        @gc = {}
        @curr = {}
        @timeout = timeout
        @keeper = keeper
      end

      def add(obj)
        synchronize do
          key = if obj.respond_to?(:drb_name)
                  obj.drb_name
                else
                  "#{obj.class.to_s.downcase}_#{obj.__id__}".to_sym
                end
          @curr[key] = obj
          @gc.delete(key)
          return key
        end
      end

      def fetch(key, dv=@sentinel)
        synchronize do
          obj = peek(key)
          if obj == @sentinel
            return dv unless dv == @sentinel
            raise InvalidIndexError
          end
          return obj
        end
      end

      def include?(key)
        synchronize do
          obj = peek(key)
          return false if obj == @sentinel
          true
        end
      end

      def peek(key)
        synchronize do
          obj = @curr.fetch(key, nil)
          return obj if obj

          obj = @gc.fetch(key, nil)
          if obj
            @gc.delete(key)
            @curr[key] = obj
            return obj
          end

          class_name, params = Marshal.load(key) rescue [nil, nil]
          if DRB_NEW_OBJS.include?(class_name)
             clazz = class_name.split('::').inject(Object) {|o,c| o.const_get c}
             obj = clazz.send(:new, *params)
             @curr[key] = obj
             return obj 
          end

          return @sentinel
        end
      end

      private
      def alternate
        synchronize do
          @gc.each{|key, gc_obj| gc_obj.gc_hooks if gc_obj.respond_to?(:gc_hooks)}
          @gc = @curr       # GCed
          @curr = {}
        end
      end

      def keeper
        Thread.new do
          loop do
            alternate
            sleep(@timeout)
          end
        end
      end
    end

    # Creates a new TimerIdConv which will hold objects for +timeout+ seconds.
    def initialize(timeout=600)
      @holder = NameTimerHolder.new(timeout)
    end

    def to_obj(ref) # :nodoc:
      return super if ref.nil?
      @holder.fetch(ref)
    rescue NameTimerHolder::InvalidIndexError
      super
    end

    def to_id(obj) # :nodoc:
      #return super unless obj.respond_to?(:drb_name) || obj.is_a?(Array) || obj.is_a?(DRbArray) || obj.is_a?(Hash)
      return @holder.add(obj)
    end

    def do_keeper
      @holder.send(:keeper)
    end

  end
end

# DRb.install_id_conv(TimerIdConv.new)
