FROM ubuntu:xenial

RUN apt-get update
RUN apt-get install -y git-core build-essential
RUN apt-get install -y g++-aarch64-linux-gnu gcc-aarch64-linux-gnu \
  g++-arm-linux-gnueabihf gcc-arm-linux-gnueabihf
RUN apt-get install -y device-tree-compiler
RUN apt-get install -y dos2unix
