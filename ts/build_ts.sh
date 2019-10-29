#!/usr/bin/env sh

# Using tip from https://stackoverflow.com/a/51186557/1502174

docker build -t build_ts .
docker create -ti --name dummy build_ts bash
docker cp dummy:/app/ts  ts
docker cp dummy:/app/ts.1  ts.1
docker rm -f dummy
