FROM ubuntu:24.04
#FROM node:24-bookworm-slim

LABEL org.opencontainers.image.title="ckpool-solo"
LABEL org.opencontainers.image.description="ckpool (solo) - runtime build with CPU-specific optimizations"
LABEL org.opencontainers.image.authors="Philip D'Ath, pidath007@gmail"

# Runtime script: at container start this will compile using -march=native
# (to use host CPU optimisations), then run ckpool as the unprivileged
# `ckpool` user. The script will attempt to remove build artifacts and
# purge build deps to reduce disk usage in the container layer.
RUN cat <<'EOF' >/usr/local/bin/run.sh
#!/bin/bash

BUILD_DEPS=(
    build-essential
    yasm
    libtool
    autotools-dev
    automake
    pkg-config
    libzmq3-dev
    libevent-dev
    bsdmainutils
    libssl-dev
    git
    ca-certificates
    libcap2-bin
)

# If set to true we need to build ckpool-solo
buildRequired=false

# Check to see if there is an update to ckpool-solo
if [[ -d "/opt/ckpool" ]]; then
  cd /opt/ckpool

  # 1. Get the local hash for 'solobtc'
  LOCAL_HASH=$(git rev-parse master)

  # 2. Get the remote hash from the server (using ls-remote)
  # We use 'awk' to extract just the first column (the hash)
  REMOTE_HASH=$(git ls-remote origin master | awk '{print $1}')

  if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
      echo "ckpool-solo is up to date."
  else
      echo "There are updates to ckpool-solo.  Will trigger a new build."
      buildRequired=true
  fi

  cd /
fi

# Check if the ckpool-solo executable exists, if not, we need to build it
if [ ! -f /usr/local/bin/ckpool ]; then
      buildRequired=true
fi

# Check if a condition has been triggered that requires a build.
# This allows for a CPU-specific version to be built at container start,
# or if a new version of ckpool-solo is released.
if $buildRequired; then
    # Install or update existing build tools
    apt-get update
    apt-get install -y --no-install-recommends apt-utils netcat-openbsd
    apt-get install -y --no-install-recommends "${BUILD_DEPS[@]}"

    rm -rf /opt/ckpool # Remove any existing old version
    git clone --depth 1 https://bitbucket.org/ckolivas/ckpool.git /opt/ckpool
    cd /opt/ckpool
    ./autogen.sh
    ./configure CFLAGS="-O2 -Wall -march=native"
    make -j$(nproc)
    make install

    # Remove apt-get lists to save space
    rm -rf /var/lib/apt/lists/*

    # Setup directories
    mkdir -p /var/log/ckpool /etc/ckpool
    chown ckpool:ckpool /var/log/ckpool

    # "Disable" logging to a file.  Rely on Docker log management.
    # ln -sf /dev/null /var/log/ckpool/ckpool.log
fi

# If ckpool.conf is not present, warn (user should mount it).
if [ ! -f /etc/ckpool/ckpool.conf ]; then
  echo "Warning: /etc/ckpool/ckpool.conf not found — container will likely fail unless you mount a config." >&2
fi

# Rotate the log files ignoring any errors
LOG=/var/log/ckpool/ckpool.log
mv "$LOG".{3,4} "$LOG".{2,3} "$LOG".{1,2} "$LOG" "$LOG.1" 2>/dev/null || :

# Run ckpool in solo mode in a limited user account
su ckpool -c "ckpool -B -c /etc/ckpool/ckpool.conf"
EOF


RUN \
chmod +x /usr/local/bin/run.sh && \
# Create an account to run the service
#useradd -m -s /bin/bash ckpool && \
usermod -l ckpool ubuntu && \
groupmod -n ckpool ubuntu && \
# Remove CR in case this was edited on Windows
sed -i 's/\r$//' /usr/local/bin/run.sh

# Run ckpool in solo mode.
# The user must mount a ckpool.conf file to /etc/ckpool/ckpool.conf
CMD ["/usr/local/bin/run.sh"]

# ckpool default port
EXPOSE 3333 3433 4334