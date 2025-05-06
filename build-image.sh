#!/usr/bin/env bash
docker build --progress=plain --build-arg PACKAGES="linux-virt postgresql16 haveged qemu-guest-agent" --build-arg SERVICES="haveged" --output=type=local,dest=/tmp/pack examples/x86_64-alpine/image
