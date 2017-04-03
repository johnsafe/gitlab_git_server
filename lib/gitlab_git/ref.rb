module Gitlab
  module Git
    class Ref
      def utf8_name
        self.name
      end
    end
  end
end
