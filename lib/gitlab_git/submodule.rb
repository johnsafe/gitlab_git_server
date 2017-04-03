module Gitlab
  module Git
    class Submodule
      include EncodingHelper
      attr_accessor :basename, :url, :id

      def initialize(options)
        %w(id basename url).each do |key|
          self.send("#{key}=", options[key.to_sym])
        end
      end
      def name
        @basename
      end
    end
  end
end
