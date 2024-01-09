#!/bin/bash

set -e

current_version=$(ruby -e "require '$(pwd)/lib/inst_access/version.rb'; puts InstAccess::VERSION;")

if gem list --exact inst_access --remote --all | grep -o '\((.*)\)$' | tr '() ,'  '\n' | grep -xF "$current_version"; then
  echo "Gem has already been published ... skipping ..."
else
  gem build ./inst_access.gemspec
  find inst_access-*.gem | xargs gem push
fi
