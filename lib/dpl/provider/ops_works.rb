require 'timeout'

module DPL
  class Provider
    class OpsWorks < Provider
      requires 'aws-sdk'
      experimental 'AWS OpsWorks'

      DEFAULT_REGION = 'us-east-1'

      def client
        @client ||= Aws::OpsWorks::Client.new(region: region, credentials: credentials)
      end

      def needs_key?
        false
      end

      def check_app

      end

      def access_key_id
        options[:access_key_id] || context.env['AWS_ACCESS_KEY_ID'] || raise(Error, "missing access_key_id")
      end

      def secret_access_key
        options[:secret_access_key] || context.env['AWS_SECRET_ACCESS_KEY'] || raise(Error, "missing secret_access_key")
      end

      def region
        options[:region] || DEFAULT_REGION
      end

      def setup_auth
        @credentials ||= Aws::Credentials.new(access_key_id, secret_access_key)
      end

      alias credentials setup_auth

      def check_auth
        setup_auth
        log "Logging in with Access Key: #{option(:access_key_id)[-4..-1].rjust(20, '*')}"
      end

      def custom_json
        options[:custom_json] || {
          deploy: {
            ops_works_app.shortname => {
              migrate: !!options[:migrate],
              scm: {
                revision: current_sha
              }
            }
          }
        }
      end

      def current_sha
        @current_sha ||= `git rev-parse HEAD`.chomp
      end

      def ops_works_app
        @ops_works_app ||= fetch_ops_works_app
      end

      def fetch_ops_works_app
        data = client.describe_apps(app_ids: [option(:app_id)]).apps
        unless data.apps && data.apps.count == 1
          raise Error, "App #{option(:app_id)} not found.", error.backtrace
        end
        data.apps.first
      end

      def push_app
        Timeout::timeout(600) do
          create_deployment
        end
      rescue Timeout::Error
        error 'Timeout: Could not finish deployment in 10 minutes.'
      end

      def create_deployment
        deployment_config = {
          stack_id: ops_works_app.stack_id,
          app_id: option(:app_id),
          command: {name: 'deploy'},
          comment: travis_deploy_comment,
          custom_json: custom_json.to_json
        }
        if !options[:instance_ids].nil?
          deployment_config[:instance_ids] = Array(option(:instance_ids))
        end
        data = client.create_deployment(deployment_config)
        log "Deployment created: #{data[:deployment_id]}"
        return unless options[:wait_until_deployed]
        print "Deploying "
        deployment = wait_until_deployed(data[:deployment_id])
        print "\n"
        if deployment[:status] == 'successful'
          log "Deployment successful."
        else
          error "Deployment failed."
        end
      end

      def wait_until_deployed(deployment_id)
        deployment = nil
        loop do
          result = client.describe_deployments(deployment_ids: [deployment_id])
          deployment = result[:deployments].first
          break unless deployment[:status] == "running"
          print "."
          sleep 5
        end
        deployment
      end

      def travis_deploy_comment
        "Deploy build #{context.env['TRAVIS_BUILD_NUMBER'] || current_sha} via Travis CI"
      end

      def deploy
        super
      rescue Aws::OpsWorks::Errors::ServiceError => error
        raise Error, "Stopping Deploy, OpsWorks error: #{error.message}", error.backtrace
      end
    end
  end
end
