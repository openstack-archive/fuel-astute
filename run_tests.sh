#!/bin/bash
# astute_rspec_check.sh
# RVM
source ~/.bash_profile

set -e

# change dir to the path of the directory in which a current bash script is located
# source: http://stackoverflow.com/a/179231/842168
function cd_workspace() {
  SCRIPT_PATH="${BASH_SOURCE[0]}";
  if ([ -h "${SCRIPT_PATH}" ]) then
    while([ -h "${SCRIPT_PATH}" ]) do cd `dirname "$SCRIPT_PATH"`; SCRIPT_PATH=`readlink "${SCRIPT_PATH}"`; done
  fi
  cd `dirname ${SCRIPT_PATH}` > /dev/null
}

function license_check() {
  # License information must be in every source file
  cd_workspace

  tmpfile=`tempfile`
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
  bundle exec rake spec:unit
}

license_check
ruby_checks
