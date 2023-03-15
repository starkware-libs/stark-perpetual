FROM ciimage/python:3.9 as base_image

RUN apt update && apt install -y make libgmp3-dev g++ python3-pip python3.9-dev npm unzip
# Installing cmake via apt doesn't bring the most up-to-date version.
RUN pip install cmake==3.22
RUN curl -sL https://deb.nodesource.com/setup_12.x -o nodesource_setup.sh && bash nodesource_setup.sh && apt install -y nodejs

COPY . /app/

# Build.
WORKDIR /app/
RUN rm -rf build
RUN ./build.sh

FROM base_image

# Run tests.
WORKDIR /app/build/Release
RUN ctest -V

WORKDIR /app/src/services/perpetual/public/js/
RUN npm install -g yarn
RUN yarn install
RUN yarn test

WORKDIR /app/
