# ==============================================================================
# Stage 1: Build rippled from source
# ==============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    cmake \
    g++ \
    gcc \
    git \
    libssl-dev \
    pkg-config \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install 'conan<2'

# Set up Conan profile for building
RUN conan profile new default --detect \
    && conan profile update settings.compiler.cppstd=20 default \
    && conan profile update settings.compiler.libcxx=libstdc++11 default

RUN git clone --branch 2.3.0 --depth 1 https://github.com/XRPLF/rippled.git /rippled-src

WORKDIR /rippled-src

# Export custom Conan recipes required by rippled
RUN conan export external/snappy snappy/1.1.10@ \
    && conan export external/rocksdb rocksdb/6.29.5@ \
    && conan export external/soci soci/4.0.3@ \
    && conan export external/nudb nudb/2.0.8@

RUN mkdir .build

WORKDIR /rippled-src/.build

RUN conan install .. --output-folder . --build missing --settings build_type=Release

RUN cmake -DCMAKE_TOOLCHAIN_FILE:FILEPATH=build/generators/conan_toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    ..

RUN cmake --build . --parallel $(nproc)

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy the built rippled binary
COPY --from=builder /rippled-src/.build/rippled /usr/local/bin/rippled

# Create required directories
RUN mkdir -p /etc/rippled /var/lib/rippled/db /var/log/rippled

# Copy configuration files
COPY rippled.cfg /etc/rippled/rippled.cfg
COPY validators.txt /etc/rippled/validators.txt

# WebSocket public
EXPOSE 6006
# JSON-RPC
EXPOSE 5005

ENTRYPOINT ["rippled"]
CMD ["--conf", "/etc/rippled/rippled.cfg", "-a", "--start"]
