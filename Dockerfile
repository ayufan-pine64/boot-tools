FROM ubuntu:xenial

RUN apt-get update
RUN apt-get install -y git-core build-essential
RUN apt-get install -y g++-4.9-aarch64-linux-gnu gcc-4.9-aarch64-linux-gnu \
  g++-4.7-arm-linux-gnueabihf gcc-4.7-arm-linux-gnueabihf
RUN apt-get install -y device-tree-compiler
RUN apt-get install -y dos2unix
