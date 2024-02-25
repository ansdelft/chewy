lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'chewy/version'

Gem::Specification.new do |spec|
  spec.name          = 'chewy'
  spec.version       = Chewy::VERSION
  spec.authors       = ['Toptal, LLC', 'pyromaniac']
  spec.email         = ['open-source@toptal.com', 'kinwizard@gmail.com']
  spec.summary       = 'OpenSearch ODM client wrapper based on Elasticsearch'
  spec.description   = 'Chewy provides functionality for Elasticsearch index handling, documents import mappings and chainable query DSL.'
  spec.homepage      = 'https://github.com/toptal/chewy'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($RS)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 5.2'
  spec.add_dependency 'opensearch-dsl', '>= 0.2.1'
  spec.add_dependency 'opensearch-ruby', '>= 2.1.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
