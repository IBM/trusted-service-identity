#!/bin/bash

TSI_VERSION=$(cat ./tsi-version.txt )

ALL="all"
PUSH=""

if [ "$1" == "fast" ]; then
   ALL="fast"
elif [ "$1" == "push" ]; then
  PUSH="push"
fi

if [ "$2" == "fast" ]; then
   ALL="fast"
elif [ "$2" == "push" ]; then
  PUSH="push"
fi
# if [ "$KUBECONFIG" == "" ]; then
#   echo "KUBECONFIG must be set!"
#   exit 1
# fi

run() {
  local CMD=$1
  $CMD
  RT=$?
  if [ $RT -ne 0 ] ; then
     echo "($CMD) failed!"
     exit 1
  fi
}
