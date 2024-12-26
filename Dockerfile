# Start with our existing Go base
FROM golang:1.22-bookworm

# Install essential tools that we can actually use
RUN apt-get update && apt-get install -y \
    clang \
    lldb \
    gdb \
    cmake \
    ninja-build \
    python3 \
    python3-pip \
    git \
    curl \
    wget \
    strace \
    ltrace \
    tcpdump \
    && rm -rf /var/lib/apt/lists/*

# Set up DragonFly BSD development environment
WORKDIR /usr/local/dragonfly

# Download DragonFly BSD source and toolchain
RUN wget https://mirror-master.dragonflybsd.org/dports/dragonfly-64-6.4.0/LATEST/All/base-toolchain-6.4.0.tzst \
    && tar xf base-toolchain-6.4.0.tzst \
    && rm base-toolchain-6.4.0.tzst

# Set up Go environment for cross-compilation
ENV GOOS=dragonfly
ENV GOARCH=amd64
ENV CGO_ENABLED=1
ENV CC=clang
ENV CXX=clang++
ENV CGO_CFLAGS="-I/usr/local/dragonfly/usr/include -I/usr/local/dragonfly/usr/src/sys"
ENV CGO_LDFLAGS="-L/usr/local/dragonfly/usr/lib"

# Create workspace structure that matches production needs
WORKDIR /workspace
RUN mkdir -p \
    src/cluster \
    src/network \
    src/hammer2 \
    build \
    test \
    scripts

# Create practical development config
RUN echo '{\n\
    "development": {\n\
        "build": {\n\
            "debug_symbols": true,\n\
            "optimization_level": 0,\n\
            "warnings_as_errors": true\n\
        },\n\
        "testing": {\n\
            "test_timeout": "5m",\n\
            "parallel_tests": 4,\n\
            "coverage_enabled": true\n\
        },\n\
        "paths": {\n\
            "source": "/workspace/src",\n\
            "build": "/workspace/build",\n\
            "test_output": "/workspace/test/results"\n\
        }\n\
    }\n\
}' > /workspace/dev-config.json

# Add practical build script
RUN echo '#!/bin/bash\n\
\n\
BUILD_TYPE=$1\n\
TARGET=$2\n\
\n\
case $BUILD_TYPE in\n\
    "debug")\n\
        export CGO_CFLAGS="$CGO_CFLAGS -g -O0"\n\
        export GOGC=off\n\
        export GODEBUG=gctrace=1\n\
        ;;\n\
    "release")\n\
        export CGO_CFLAGS="$CGO_CFLAGS -O2"\n\
        export GOGC=100\n\
        ;;\n\
    *)\n\
        echo "Usage: $0 {debug|release} target"\n\
        exit 1\n\
        ;;\n\
esac\n\
\n\
echo "Building $TARGET in $BUILD_TYPE mode..."\n\
go build -v -o /workspace/build/$TARGET /workspace/src/$TARGET\n\
' > /workspace/scripts/build.sh \
&& chmod +x /workspace/scripts/build.sh

# Add practical test script
RUN echo '#!/bin/bash\n\
\n\
TEST_TYPE=$1\n\
TARGET=$2\n\
\n\
case $TEST_TYPE in\n\
    "unit")\n\
        go test -v ./src/$TARGET/... \n\
        ;;\n\
    "coverage")\n\
        go test -v -coverprofile=/workspace/test/coverage.out ./src/$TARGET/... \n\
        ;;\n\
    *)\n\
        echo "Usage: $0 {unit|coverage} target"\n\
        exit 1\n\
        ;;\n\
esac\n\
' > /workspace/scripts/test.sh \
&& chmod +x /workspace/scripts/test.sh

# Create development tools script
RUN echo '#!/bin/bash\n\
\n\
function setup_debug() {\n\
    echo "Setting up debug environment..."\n\
    export GOTRACEBACK=all\n\
    export GODEBUG=gctrace=1\n\
}\n\
\n\
function run_analysis() {\n\
    echo "Running code analysis..."\n\
    go vet ./...\n\
    golint ./...\n\
}\n\
\n\
function run_memory_check() {\n\
    echo "Running memory checks..."\n\
    go test -memprofile=mem.out ./...\n\
}\n\
\n\
case "$1" in\n\
    "debug")\n\
        setup_debug\n\
        ;;\n\
    "analyze")\n\
        run_analysis\n\
        ;;\n\
    "memcheck")\n\
        run_memory_check\n\
        ;;\n\
    *)\n\
        echo "Usage: $0 {debug|analyze|memcheck}"\n\
        ;;\n\
esac\n\
' > /workspace/scripts/devtools.sh \
&& chmod +x /workspace/scripts/devtools.sh

WORKDIR /workspace

# Create entrypoint script
RUN echo '#!/bin/bash\n\
echo "DragonFlyBSD Go Development Environment"\n\
echo "\nAvailable commands:"\n\
echo "1. ./scripts/build.sh {debug|release} target  # Build project"\n\
echo "2. ./scripts/test.sh {unit|coverage} target   # Run tests"\n\
echo "3. ./scripts/devtools.sh {debug|analyze|memcheck}  # Development tools"\n\
echo "\nEnvironment configured for DragonFlyBSD development:"\n\
echo "- GOOS=$GOOS"\n\
echo "- GOARCH=$GOARCH"\n\
echo "- CGO_ENABLED=$CGO_ENABLED"\n\
exec "$@"' > /entrypoint.sh \
&& chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
