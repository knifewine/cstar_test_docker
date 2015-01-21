#!/bin/bash
# The purpose of this script is to build a docker container for a specific cassandra git ref
# It attempts to use the docker cache system as much as possible without building stale code
# It creates git_sha.txt which is created to preserve or invalidate the docker cache when appropriate
# Most importantly it creates the Dockerfile which is used to build the docker image
# To make changes to the build steps, edit Dockerfile.template but be aware this will likely invalidate caches and make things take longer
if [ "$#" -eq 0 ]; then
    echo
    echo "usage: "
    echo
    echo "$0 some_git_branch"
    echo " OR"
    echo "$0 some_git_tag"
    echo " OR"
    echo "$0 some_git_commit (Note that the validity of the commit id isn't checked before attempting building)."
    echo
    exit 0
fi;

GIT_SEARCH=$1 # user provided branch/tag/commit 
GIT_SHA=`git ls-remote -h -t https://github.com/apache/cassandra.git $GIT_SEARCH`

if [ -z "$GIT_SHA" ]; then
    echo "$GIT_SEARCH does not seem to be a branch or tag. Will attempt to build using value as commit id."
    # we can't correlate the ref to a tag/branch, so lets set the SHA value to the user provided value which is now assumed to be a commitd$ SHA
    GIT_SHA=$GIT_SEARCH
fi

# git_sha.txt will be used to invalidate the cache as needed
# trim off the branch/tag from the git ls-remote output
echo ${GIT_SHA:0:40} > git_sha.txt

# hack to set same times on file, prevent unnecessary docker cache invalidation
touch -d 2015-01-1 git_sha.txt

# Create new Dockerfile and add a note so no one edits it directly
echo "# NOTE: this file is auto-generated! To make changes edit Dockerfile.template instead!" > Dockerfile

# update Dockerfile to set git ref
sed s/{{git_ref_to_build}}/$GIT_SEARCH/g Dockerfile.template >> Dockerfile

# this just means the user provided git ref wasn't a tag or branch name
if [ "$GIT_SEARCH" = "$GIT_SHA" ]; then
    GIT_SEARCH='commit'
fi

# this will run the Dockerfile and build the image
docker build -t cstar/openjdk:${GIT_SEARCH}_${GIT_SHA:0:10} .
