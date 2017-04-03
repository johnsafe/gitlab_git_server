module Gitlab
  module Git
    class Tag < Ref
      include EncodingHelper
      attr_reader :message, :created_at

      def initialize(name, target, message = nil, rugged_ref=nil,created_at=nil)
        super(name, target)
        @message = message
        @created_at = created_at
      end

    end
  end
end
