FROM ghcr.io/linuxserver/baseimage-fedora:36 as buildstage

ARG XRDP_PULSE_VERSION=v0.6

RUN \
  echo "**** install build deps ****" && \
  dnf groupinstall -y \
    "Development Tools" && \
  dnf install -y \
    'dnf-command(builddep)' \
    'dnf-command(download)' \
    libtool \
    rpmdevtools \
    wget \
    yum-utils && \
  dnf install -y \
    pulseaudio \
    pulseaudio-libs \
    pulseaudio-libs-devel && \
  dnf builddep -y \
    pulseaudio

RUN \
  echo "**** fetch pulseaudio source ****" && \
  dnf download --source -y \
    pulseaudio && \
  rpm --install \
    pulseaudio*.src.rpm

RUN \
  echo "**** run pulseaudio meson build ****" && \
  VERSION=$(ls -1 /root/rpmbuild/SOURCES/*.tar.xz | \
    awk -F '(pulseaudio-|.tar.xz)' '/pulseaudio-/ {print $2; exit}') && \
  cd ~/rpmbuild/SOURCES/ && \
  tar -xf pulseaudio-${VERSION}.tar.xz && \
  cd pulseaudio-${VERSION} && \
  meson build

RUN \
  echo "**** build pulseaudio xrdp module ****" && \
  VERSION=$(ls -1 /root/rpmbuild/SOURCES/*.tar.xz | \
    awk -F '(pulseaudio-|.tar.xz)' '/pulseaudio-/ {print $2; exit}') && \
  mkdir -p /tmp/buildout/usr/lib64/pulse-${VERSION}/modules/ && \
  wget \
    https://github.com/neutrinolabs/pulseaudio-module-xrdp/archive/refs/tags/${XRDP_PULSE_VERSION}.tar.gz \
    -O /tmp/pulsemodule.tar.gz && \
  cd /tmp && \
  tar -xf pulsemodule.tar.gz && \
  cd pulseaudio-module-xrdp-* && \
  ./bootstrap && \
  ./configure \
    PULSE_DIR=/root/rpmbuild/SOURCES/pulseaudio-${VERSION} && \
  make && \
  install -t "/tmp/buildout/usr/lib64/pulse-${VERSION}/modules/" -D -m 644 src/.libs/*.so

# docker compose
FROM ghcr.io/linuxserver/docker-compose:amd64-latest as compose

# runtime stage
FROM ghcr.io/linuxserver/baseimage-fedora:36

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# copy over libs and installers from build stage
COPY --from=buildstage /tmp/buildout/ /
COPY --from=compose /usr/local/bin/docker-compose /usr/local/bin/docker-compose

#Add needed nvidia environment variables for https://github.com/NVIDIA/nvidia-docker
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

RUN \
  echo "**** install deps ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    dbus-x11 \
    docker \
    openssh-clients \
    openssl \
    pavucontrol \
    pulseaudio \
    sudo \
    xorg-x11-drv-amdgpu \
    xorg-x11-drv-intel \
    xorg-x11-drv-ati \
    xorgxrdp \
    xrdp \
    xterm && \
  VERSION=$(ls -1 /usr/lib64/ | \
    awk -F '-' '/pulse-/ {print $2; exit}') && \
  ldconfig -n /usr/lib64/pulse-${VERSION}/modules && \
  echo "**** cleanup and user perms ****" && \
  echo "abc:abc" | chpasswd && \
  usermod -s /bin/bash abc && \
  echo '%wheel ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/wheel && \
  usermod -aG wheel abc && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3389
VOLUME /config
