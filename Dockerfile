FROM ubuntu:18.04

RUN apt update
RUN apt install -y cmake python3.7 libgmp3-dev g++ python3-pip python3.7-dev npm

COPY . /app/

# Build.
WORKDIR /app/
RUN ./build.sh

# Run tests.
WORKDIR /app/build/Release
RUN ctest -V

WORKDIR /app/
