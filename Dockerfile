FROM ciimage/python:3.9 as base_image

RUN apt update && apt install -y git make libgmp3-dev g++ python3-pip python3.9-dev npm unzip
# Installing cmake via apt doesn't bring the most up-to-date version.
RUN pip install cmake==3.22
RUN curl -sL https://deb.nodesource.com/setup_18.x -o nodesource_setup.sh && bash nodesource_setup.sh && apt install -y nodejs

COPY . /app/
WORKDIR /app/
RUN ./docker_common_deps.sh

# Build.
RUN bazel build //...

FROM base_image

# Run tests.
RUN bazel test //...

WORKDIR /app/src/services/perpetual/public/js/
RUN npm install -g yarn
RUN yarn install
RUN yarn test

WORKDIR /app/
