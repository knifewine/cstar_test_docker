#!/bin/bash
# The purpose of this script is to build a docker container for a specific cassandra git ref
# It attempts to use the docker cache system as much as possible without building stale code
# It creates git_sha.txt which is created to preserve or invalidate the docker cache when appropriate
# Most importantly it creates the Dockerfile which is used to build the docker image
# To make changes to the build steps, edit Dockerfile.template but be aware this will likely invalidate caches and make things take longer

if [ -z $1 ]; then
    echo
    echo "usage: "
    echo
    echo "$0 [some_git_ref]"
    echo
    exit 0
fi;

GIT_REF=$1
GIT_SHA=`git ls-remote -h -t https://github.com/apache/cassandra.git $GIT_REF`

if [ -z "$GIT_SHA" ]; then
    echo "$GIT_REF does not seem to be valid, exiting"
    exit 1
fi

# git_sha.txt will be used to invalidate the cache as needed
echo $GIT_SHA > git_sha.txt

# hack to set same times on file, prevent unnecessary docker cache invalidation
touch -d 2015-01-1 git_sha.txt

# add a note to the Dockerfile so no one edits it directly
echo "# NOTE: this file is auto-generated! To make changes edit Dockerfile.template instead!" > Dockerfile

# update Dockerfile to set git ref and for specific jvm
sed s/{{git_ref_to_build}}/$GIT_REF/g Dockerfile.template >> Dockerfile

# this will run the Dockerfile and build the image
#docker build .
