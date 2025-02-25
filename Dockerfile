# Builder stage
ARG BUILDPLATFORM
FROM --platform=$BUILDPLATFORM debian:bullseye-slim AS builder

# Redeclare ARGs for this stage
ARG ARCH
ARG TARGETARCH

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install common build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    qt5-qmake \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install architecture-specific dependencies
RUN dpkg --add-architecture $TARGETARCH \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        crossbuild-essential-$TARGETARCH \
        openssl:$TARGETARCH \
        zlib1g-dev:$TARGETARCH \
        libbz2-dev:$TARGETARCH \
        libjemalloc-dev:$TARGETARCH \
        libzmq3-dev:$TARGETARCH \
        qtbase5-dev:$TARGETARCH \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone and build Fulcrum
RUN git clone --branch v1.11.1 --depth 1 https://github.com/cculianu/Fulcrum.git .

RUN $ARCH-linux-gnu-qmake -makefile PREFIX=/usr \
        "QMAKE_CXXFLAGS_RELEASE -= -O3" \
        "QMAKE_CXXFLAGS_RELEASE += -O1" \
        "LIBS += -L/src/staticlibs/rocksdb/bin/linux/$ARCH" \
        Fulcrum.pro \
    && make -j$(nproc) install \
    && $ARCH-linux-gnu-strip Fulcrum;

# Final stage
FROM debian:bullseye-slim

# Redeclare necessary ARGs - make sure these are passed during build
ARG ARCH
ARG TARGETARCH

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    DATA_DIR=/data \
    SSL_CERTFILE=/data/fulcrum.crt \
    SSL_KEYFILE=/data/fulcrum.key

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssl \
        libqt5network5 \
        zlib1g \
        libbz2-1.0 \
        libjemalloc2 \
        libzmq5 \
        tini \
        wget \
        curl \
        netcat \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy binary and scripts
COPY --from=builder /src/Fulcrum /usr/bin/Fulcrum
COPY ./docker_entrypoint.sh /usr/local/bin/
COPY ./health-check/*.sh /usr/local/bin/

# Install yq and configurator (keeping ${TARGETARCH} for proper multi-arch support)
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH} \
    && chmod +x /usr/local/bin/yq /usr/local/bin/*.sh

# Add configurator last since it's likely to change often
COPY ./configurator/target/${ARCH}-unknown-linux-musl/release/configurator /usr/local/bin/configurator

# Define volume
VOLUME ["/data"]

# Set entrypoint
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker_entrypoint.sh"]