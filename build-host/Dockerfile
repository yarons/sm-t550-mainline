FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 git ca-certificates sudo openssl procps util-linux kpartx e2fsprogs dosfstools \
    tar xz-utils zstd kmod file less openssh-client multipath-tools android-sdk-libsparse-utils \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash pmos && echo 'pmos ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/pmos
RUN git clone --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git /opt/pmbootstrap \
 && ln -s /opt/pmbootstrap/pmbootstrap.py /usr/local/bin/pmbootstrap
USER pmos
WORKDIR /home/pmos
