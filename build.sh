#!/bin/bash

processors=3

if [ -n "$1" ]
then
  for i in $*
  do
    case $i in
      [1-9]|[0-9][0-9])
        processors=$i
        ;;
      *)
        modules=vaadin-$i-flow-parent/vaadin-$i-flow-integration-tests,$modules
        elements="$elements $i"
       ;;
     esac
  done
fi

tcMsg() (
  { set +x; } 2> /dev/null
  echo "##teamcity[$1]"
)
# open a block in the TC tree output
tcLog() {
  [ -n "$inblock" ] && tcMsg "blockClosed name='$inblock'"
  inblock="$1"
  tcMsg "blockOpened name='$inblock'"
}
# log in TC
tcStatus() {
  { set +x; } 2> /dev/null
  [ "$1" = "0" ] && status=SUCCESS || status=FAILURE
  tcMsg "buildStatus status='$status' text='$1'"
}

tcLog 'Show info'
java -version
mvn -version
node --version
npm --version
uname -a

cmd="npm install --silent --quiet --no-progress"
tcLog "Install NPM packages - $cmd"
$cmd

cmd="node scripts/mergeITs.js "`echo $elements`
tcLog "Merge IT modules - $cmd"
$cmd

cmd="mvn install -DskipTests -Drelease -B -T C$processors"
tcLog "Installing flow components - $cmd"
$cmd

if [ -n "$BUILD" ]
then
  cmd="mvn test -B -Drun-it -T C$processors"
  tcLog "Unit-Testing - $cmd"
  $cmd
fi

[ -n "$TBLICENSE" ] && args="$args -Dvaadin.testbench.developer.license=$TBLICENSE"
[ -n "$TBHUB" ] && args="$args -Dtest.use.hub=true -Dcom.vaadin.testbench.Parameters.hubHostname=$TBHUB"

echo "$args"

if [ "$TBHUB" = "localhost" ]
then
    tcLog 'Installing docker image with standalone-chrome'
    trap "echo Terminating docker; docker stop standalone-chrome" EXIT
    docker pull selenium/standalone-chrome
    docker image prune -f
    docker run --name standalone-chrome --net=host --rm -d -v /dev/shm:/dev/shm  selenium/standalone-chrome
fi

args="$args -Dfailsafe.forkCount=$processors"

if [ -n "$modules" ]
then
  ### Run IT's in original modules
  cmd="mvn clean verify $args -pl $modules"
  tcLog "Running module ITs - mvn clean verify -pl ..."
  echo $cmd
  $cmd
elif [ -z "$BUILD" ]
then
  ### Run IT's in merged module
  cmd="mvn verify -Drun-it -Drelease -Dcom.vaadin.testbench.Parameters.testsInParallel=1 $args -pl integration-tests"
  tcLog "Running merged ITs - mvn verify -Drun-it -Drelease -pl integration-tests ..."
  echo $cmd
  $cmd
fi