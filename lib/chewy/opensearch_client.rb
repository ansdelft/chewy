module Chewy
  # Replacement for Chewy.client
  class OpensearchClient
    def self.build_os_client(configuration = Chewy.configuration)
      client_configuration = configuration.deep_dup
      client_configuration.delete(:prefix) # used by Chewy, not relevant to Elasticsearch::Client
      block = client_configuration[:transport_options].try(:delete, :proc)
      ::OpenSearch::Client.new(client_configuration, &block)
    end

    def initialize(opensearch_client = self.class.build_os_client)
      @opensearch_client = opensearch_client
    end

  private

    def method_missing(name, *args, **kwargs, &block)
      inspect_payload(name, args, kwargs)

      @opensearch_client.__send__(name, *args, **kwargs, &block)
    end

    def respond_to_missing?(name, _include_private = false)
      @opensearch_client.respond_to?(name) || super
    end

    def inspect_payload(name, args, kwargs)
      Chewy.config.before_os_request_filter&.call(name, args, kwargs)
    end
  end
end
