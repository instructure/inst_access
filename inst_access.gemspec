# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative 'lib/inst_access/version'

Gem::Specification.new do |spec|
  spec.name                  = 'inst_access'
  spec.version               = InstAccess::VERSION
  spec.required_ruby_version = '>= 2.5'
  spec.authors               = ['Michael Ziwisky']
  spec.email                 = ['mziwisky@instructure.com']
  spec.summary               = 'Generation, parsing, and validation of Instructure access tokens'

  spec.files                 = Dir.glob('{lib,spec}/**/*') + %w[test.sh]
  spec.executables           = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files            = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths         = ['lib']
  spec.homepage              = 'http://github.com/instructure/inst_access'

  spec.add_dependency 'activesupport', '>= 5'
  spec.add_dependency 'json-jwt', '1.13.0'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop', '~> 1.8.1'
  spec.add_development_dependency 'rubocop-ast'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'simplecov-json'
  spec.add_development_dependency 'timecop'
end
