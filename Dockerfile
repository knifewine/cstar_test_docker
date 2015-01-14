# NOTE: this file is auto-generated! To make changes edit Dockerfile.template instead!
FROM ubuntu

RUN \
  apt-get update && \
  apt-get -y upgrade && \
  apt-get install -y build-essential && \
  apt-get install -y software-properties-common && \
  apt-get install -y byobu curl git htop man unzip vim wget ant python python-dev python-pip

{{jdk_setup_steps}}

# This git clone will be cached so by docker so it may get behind the actual repo, but the git pull below should bring it up to date
# You can always run docker with --no-cache to make sure this is a truly up-to-date clone
RUN git clone https://github.com/apache/cassandra.git
WORKDIR cassandra
# ADD a file with the git sha, so the docker cache will be invalidated if necessary
ADD git_sha.txt / 
RUN git pull
RUN git checkout cassandra-2.0.10 
RUN ant clean jar