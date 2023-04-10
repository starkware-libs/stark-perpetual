FROM ubuntu:18.04

RUN apt update
RUN apt -y -o Dpkg::Options::="--force-overwrite" install python3.7-dev python3.7-distutils
RUN apt install -y cmake libgmp3-dev g++ python3-pip

COPY . /app/

# Build.
WORKDIR /app/
RUN ./build.sh

# Run tests.
WORKDIR /app/build/Release
RUN ctest -V

WORKDIR /app/
