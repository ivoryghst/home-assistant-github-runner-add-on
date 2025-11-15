ARG BUILD_FROM
FROM $BUILD_FROM

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install dependencies with specific versions for reproducibility
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash=5.2.* \
    curl=7.88.* \
    git=1:2.39.* \
    jq=1.6-* \
    tar=1.34* \
    unzip=6.0-* \
    sudo=1.9.* \
    ca-certificates \
    python3=3.11.* \
    python3-pip=23.0.* \
    python3-venv=3.11.* \
    nodejs=18.* \
    npm=9.2.* \
    rsync=3.2.* \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create a non-root user for running the GitHub Actions runner
RUN useradd -m -u 1000 runner

# Set up runner directory
RUN mkdir -p /runner && chmod 755 /runner
WORKDIR /runner

# Download and install GitHub Actions Runner
ARG BUILD_ARCH
RUN set -e && \
    RUNNER_VERSION=$(curl -sSf https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//') && \
    if [ -z "$RUNNER_VERSION" ]; then \
        echo "Failed to fetch runner version" >&2; \
        exit 1; \
    fi && \
    if [ "$BUILD_ARCH" = "amd64" ]; then \
        RUNNER_ARCH="x64"; \
    elif [ "$BUILD_ARCH" = "aarch64" ]; then \
        RUNNER_ARCH="arm64"; \
    elif [ "$BUILD_ARCH" = "armv7" ] || [ "$BUILD_ARCH" = "armhf" ]; then \
        RUNNER_ARCH="arm"; \
    else \
        RUNNER_ARCH="x64"; \
    fi && \
    echo "Downloading runner for architecture: ${RUNNER_ARCH}, version: ${RUNNER_VERSION}" && \
    RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" && \
    curl -sSfL -o actions-runner.tar.gz "${RUNNER_URL}" && \
    # Download and verify checksum
    curl -sSfL -o actions-runner.tar.gz.sha256 "${RUNNER_URL}.sha256" && \
    if command -v sha256sum >/dev/null 2>&1; then \
        echo "Verifying checksum..." && \
        sha256sum -c actions-runner.tar.gz.sha256 || { \
            echo "Checksum verification failed!" >&2; \
            exit 1; \
        }; \
    else \
        echo "Warning: sha256sum not available, skipping checksum verification" >&2; \
    fi && \
    tar xzf actions-runner.tar.gz && \
    rm -f actions-runner.tar.gz actions-runner.tar.gz.sha256 && \
    ./bin/installdependencies.sh && \
    chown -R runner:runner /runner

# Copy run script
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
