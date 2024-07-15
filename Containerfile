FROM registry.redhat.io/rhel9/rhel-bootc:9.4

# Perform some basic package installation
RUN --mount=target=/var/cache,type=tmpfs --mount=target=/var/cache/dnf,type=cache,id=dnf-cache \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
 && dnf -y install \
      tmux \
      podman \
      curl \
      lm_sensors \
      btop

RUN --mount=target=/var/cache,type=tmpfs --mount=target=/var/cache/dnf,type=cache,id=dnf-cache \
    --mount=type=bind,source=qor-rpm,target=/tmp/qor-rpm \
    dnf -y install /tmp/qor-rpm/qor*.rpm

# Basic user configuration with nss-altfiles
COPY overlays/users/ /
RUN useradd -m core \
  && chown core:core /usr/local/ssh/core.keys

# Enable the deployed system to pull its own updates
COPY overlays/auth/ /
