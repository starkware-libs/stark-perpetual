FROM ciimage/python:3.9-ci as base_image

# Installing cmake via apt doesn't bring the most up-to-date version.
RUN pip install cmake==3.22
RUN curl -sL https://starkware-third-party.s3.us-east-2.amazonaws.com/build_tools/node-v18.17.0-linux-x64.tar.xz -o node-v18.17.0-linux-x64.tar.xz && \
    tar -xf node-v18.17.0-linux-x64.tar.xz -C /opt/ && \
    rm -f node-v18.17.0-linux-x64.tar.xz

ENV PATH="${PATH}:/opt/node-v18.17.0-linux-x64/bin"
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
