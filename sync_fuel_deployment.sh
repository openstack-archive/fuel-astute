#!/bin/sh
SOURCE="../fuel-deployment"

DIR=`dirname $0`
cd $DIR || exit 1

rsync -rvc --delete "${SOURCE}/lib/fuel_deployment/" "lib/fuel_deployment/"
rsync -rvc  "${SOURCE}/lib/fuel_deployment.rb" "lib/fuel_deployment.rb"
rsync -rvc --exclude="spec_helper.rb" --delete --delete-excluded "${SOURCE}/spec/" "spec/unit/fuel_deployment/"
rsync -rvc --delete "${SOURCE}/tests/" "tests/"
