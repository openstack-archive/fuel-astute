#!/bin/bash
# astute_rspec_check.sh
# RVM

set -e

function cd_workspace() {
  cd "$( cd "$( dirname "$( dirname "$0" )" )" && pwd )" > /dev/null
}

function make_tmpfile() {
  if [[ "$OSTYPE" == *darwin* ]]
  then
    echo `mktemp -t fuel-astute`
  else
    echo `mktemp`
  fi
}

function license_check() {
  # License information must be in every source file
  cd_workspace


  tmpfile=$(make_tmpfile)
  find * -not -path "docs/*" -regex ".*\.\(rb\)" -type f -print0 | xargs -0 grep -Li License
  files_with_no_license=`wc -l $tmpfile | awk '{print $1}'`
  if [ $files_with_no_license -gt 0 ]; then
    echo "ERROR: Found files without license, see files below:"
    cat $tmpfile
    rm -f $tmpfile
    exit 1
  fi
  rm -f $tmpfile
}

function ruby_checks() {
  cd_workspace

  # Install all ruby dependencies (expect ruby version manager: RVM, rbenv or similar)
  bundle install

  # Run unit rspec tests
  bundle exec rake spec:unit S=$1
}

license_check
ruby_checks $@
