#!/bin/bash
# export
# exit 1
# ~/astute_rspec_check.sh
set +x

set -e
set -u

function license_check() {
    # License information must be in every source file
    cd $WORKSPACE
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
    # Clean up work folder
    # rm -Rf mcollective_tmp *.zip
    # Installing ruby dependencies
    # Build and install mcollective client
    # mkdir mcollective_tmp
    # curl -LO https://github.com/puppetlabs/marionette-collective/archive/9f8d2ec75ba326d2a37884224698f3f96ff01629.zip
    # unzip 9f8d2ec75ba326d2a37884224698f3f96ff01629.zip -d mcollective_tmp
    # cd mcollective_tmp
    # cd marionette-collective-*
    # bundle exec rake gem
    # cd build
    # gem install *.gem
    # cd $WORKSPACE
    # 
    # # Clean up work folder
    # rm -Rf mcollective_tmp *.zip
    curl -LO https://dl.dropboxusercontent.com/u/984976/mcollective-client-2.3.1.gem
    gem install mcollective-client-2.3.1.gem
    rm mcollective-client-2.3.1.gem
    echo 'source "https://rubygems.org"' > Gemfile
    echo 'source "http://download.mirantis.com/fuelweb-repo/3.2/gems/"' >> Gemfile
    echo 'gemspec' >> Gemfile
    
    # Install all other ruby dependencies
    sudo bundle install
    
    # Run unit rspec tests
    set +e
    bundle exec rake spec:unit
    rc=$?
    set -e
    if test $rc -ne 0 ; then
      exit 1
    fi
}

license_check
ruby_checks
