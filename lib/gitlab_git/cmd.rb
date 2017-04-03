module Gitlab
  module Git
    class Cmd
      extend Gitlab::Git::Popen
      def self.set_write_methods
        [:execute]
      end

      def self.to_sym
        'cmd'.to_sym
      end

      def self.execute(path, cmd)
        raise ArgumentError.new('missing path') if path.nil?
        full_path = File.join(Settings.repository.pre_path, path)
        result = popen(cmd, full_path)
        # ProjectSyncClient.push path, (cmd =~ /^rm\s+/ ? 'delete' : 'push') if path =~ /\.git$/
        result
      end
    end
  end
end
