# cstar_test_docker
This is a really simple tool for building simple Cassandra docker containers, for test purposes.

The container does NOT currently start Cassandra automatically, because you'll probably want to tweak it, edit config, etc.

Cassandra is installed to /cassandra -- the image built will have openjdk7.

If you want the Oracle JDK have a look at oracle_jdk.txt to see how you might update the Dockerfile.tempate to do that.

The main entry point is build.sh, which just does a little bit of trickery to build a Dockerfile and then invokes docker's build process.

This was built to make the best use of Docker's caching system but hopefully without you getting any stale Cassandra source code.

#### Setup

Install docker -- on debian you can install the 'docker.io' package, or read the instructions at: https://docs.docker.com/installation/#installation

If you have trouble running docker, trying installing the apparmor package which seems to be required.

If you don't want to use sudo for everything, add your user to the 'docker' group on your computer (this is root equivalent, so don't do this if you are the paranoid type).

Run the build script with a valid branch/tag git ref from the cassandra repository (ex: 'cassandra-2.1'). This will build an image for you and build cassandra at the git ref specified. Note that git commit SHA's are supported, but are not validated ahead of container build (so the build could fail if you use a bad commit id).

    ./build.sh cassandra-2.1

Wait for the image to build. It's going to take a while, but after Docker's cache is built it should be pretty quick on subsequent runs.

The image will get automatically named something like 'cstar/openjdk:cassandra-2.0.10_23fe7e9d87'. The first portion indicates you've got Cassandra with the openjdk, the second portion shows the git ref name you used, and the git SHA it referenced at build time (because this could change in the case of a branch build). Be aware that if you use a tag, the SHA will point to the tag, not the tag's referenced commit id.

You can list the docker images with

    docker images

That will show output similar to this:

    REPOSITORY                       TAG                           IMAGE ID            CREATED             VIRTUAL SIZE
    cstar/openjdk                    cassandra-2.1_2ff9137674      711bf544f999        About an hour ago   1.167 GB

Go ahead and start a container from the image. This will take you to an interactive shell (privileged mode is likely not necessary, so you can omit that if you're the paranoid type).

    docker run -t -i --privileged=true cstar/openjdk:cassandra-2.0.10_23fe7e9d87
    
Or alternatively using the docker image ID:
    
    docker run -t -i --privileged=true 711bf544f999
    
From the container's shell, start up cassandra in the foreground to test it out:

    /cassandra/bin/cassandra -f

That's it! But read on to find out how to build a cluster and network across hosts if you need to do that.

#### Communicating between containers, building a Cassandra cluster, and making a cluster that spans multiple hosts.
    
You can start more containers from the same base image, by repeating the command above. Build a fully local container cluster by doing just that.

Containers on the same host should be able to communicate with each other without any special work, just run 'hostname -I' inside the container to find out it's IP address so you can configure it as part of a cluster.

    root@fe6ea016140e:/cassandra# hostname -I
    172.17.0.144

If you want containers spanning multiple hosts to be able to talk easily, you'll probably want [Weave](https://github.com/zettio/weave).

Follow the install instructions from the Weave git repo.

Run 'weave setup' to let weave build it's own docker image.

Run 'weave launch' to start the weave container on your docker host.

If your containers are going to span multiple hosts, run 'weave setup' on the other machines, and 'weave launch \<ip_address\>', where the ip_address is the ip of the machine already running Weave. This will connect the second Weave instance to Weave on the other host so they can figure out the network topology.

Start up your containers using Weave syntax to assign an ip address. IP's on the same subnet will be visible to each other, regardless of host running container.

    C=$(sudo weave run 10.0.1.1/24 -t -i --privileged=true cstar/openjdk:cassandra-2.0.10_23fe7e9d87)
    
Repeat the above for each Cassandra instance you want, but be sure to increment the IP addresses! Hang on to the container ID assigned above, or use 'docker ps' to see what containers are running.

To get into the containers, use 'docker attach':

    docker attach $C
    
From there you should be able to ping the other containers to check connectivity.

#### Bonus points: mucking with the container network

Within each container there will be an adapter called 'ethwe' created by Weave, which we can mess with to simulate network woes (what can I say, it's my job to confuse and break software....)

I've found I can use linux network emulation (netem) to accomplish some basic traffic trouble. Here's the [netem documentation](http://www.linuxfoundation.org/collaborate/workgroups/networking/netem).

This is still somewhat magical to me, but you can connect to each container you want to mess with and issue some basic commands to slow packets, drop, reorder, and even corrupt packets if you are extra mean.

Note that the container needs to be run in privileged mode to work with netem.

Start up two containers with weave, on 10.0.1.1 and 10.0.1.2 (omitting the second container here). Notice those fast ping times? Let's ruin those.

    rhatch@elminto:~/docker [master*]$ C1=$(sudo weave run 10.0.1.1/24 -t -i --privileged=true cstar/openjdk:cassandra-2.0.10_23fe7e9d87)
    rhatch@elminto:~/docker [master*]$ docker attach $C1
    root@8fab0a2491b1:/cassandra# 
    root@8fab0a2491b1:/cassandra# ping 10.0.1.2
    PING 10.0.1.2 (10.0.1.2) 56(84) bytes of data.
    64 bytes from 10.0.1.2: icmp_seq=1 ttl=64 time=0.187 ms
    64 bytes from 10.0.1.2: icmp_seq=2 ttl=64 time=0.044 ms
    
Issue the netem command to slow packets. Note the 'add' keyword which adds the rule, the 'ethwe' which applies it to the weave network adapter.

    root@8fab0a2491b1:/cassandra# tc qdisc add dev ethwe root netem delay 100ms
    root@8fab0a2491b1:/cassandra# ping 10.0.1.2
    PING 10.0.1.2 (10.0.1.2) 56(84) bytes of data.
    64 bytes from 10.0.1.2: icmp_seq=1 ttl=64 time=100 ms
    64 bytes from 10.0.1.2: icmp_seq=2 ttl=64 time=100 ms

You can issue a similar command on the other Cassandra container which will slow the ping to 200ms delay round trip. Note that I think these commands only slow outbound traffic -- I get the impression that slowing down or messing with inbound traffic requires more magic.

To restore normal networking, repeat the same command as before, but change 'add' to 'del', to remove the rule:

    tc qdisc del dev ethwe root netem delay 100ms

A note on MTU: it appears that the 'ethwe' adapter uses a rather large MTU of 65535. This can easily be lowered to a smaller value to cause smaller packets to be used.

    root@2605b2e3a44c:/cassandra# ifconfig ethwe | grep MTU
          UP BROADCAST RUNNING MULTICAST  MTU:65535  Metric:1
    root@2605b2e3a44c:/cassandra# ifconfig ethwe mtu 9000
    root@2605b2e3a44c:/cassandra# ifconfig ethwe | grep MTU
          UP BROADCAST RUNNING MULTICAST  MTU:9000  Metric:1

**Enjoy!**
