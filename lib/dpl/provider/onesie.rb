require 'shellwords'

module DPL
  class Provider
    class Onesie < Provider
      def push_app
        pack_archive
        upload_archive
      end

      def needs_key?
        false
      end

      def check_auth
        log "Logging in with Access Key: #{option(:key)[-4..-1].rjust(20, '*')}"
      end

      def archive_file
        Shellwords.escape("#{context.env['HOME']}/.dpl.#{option(:domain)}.tgz")
      end

      def pack_archive
        log "creating application archive"
        context.shell "tar -zvcf #{archive_file} --exclude .git ."
      end

      def put_url
        "https://www.onesie.website/upload"
      end

      def upload_archive
        log "uploading application archive"
        headers = "-H Onesie-Key:#{option(:key)} -H Onesie-Secret:#{option(:secret)} -H Onesie-Domain:#{option(:domain)}"
        command = "curl -sv #{Shellwords.escape(put_url)} -X POST #{headers} -F \"file=@#{archive_file}\""
        log command
        context.shell command
      end

      def version
        @version ||= options[:version] || context.env['TRAVIS_COMMIT'] || `git rev-parse HEAD`.strip
      end
    end
  end
end
