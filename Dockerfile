# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-fedora:40 AS buildstage

ARG XRDP_PULSE_VERSION=v0.7

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
FROM ghcr.io/linuxserver/docker-compose:amd64-latest AS compose

# runtime stage
FROM ghcr.io/linuxserver/baseimage-fedora:40

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# copy over libs and installers from build stage
COPY --from=buildstage /tmp/buildout/ /
COPY --from=compose /usr/local/bin/docker-compose /usr/local/bin/docker-compose

#Add needed nvidia environment variables for https://github.com/NVIDIA/nvidia-docker
ENV NVIDIA_DRIVER_CAPABILITIES="all" \
    HOME=/config

RUN \
  echo "**** enable locales ****" && \
  rm -f /etc/rpm/macros.image-language-conf && \
  echo "**** install deps ****" && \
  dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm && \
  dnf install -y \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
  dnf install -y 'dnf-command(config-manager)' && \
  dnf config-manager \
    --add-repo \
    https://download.docker.com/linux/fedora/docker-ce.repo && \
  echo "**** install deps ****" && \
  dnf install -y --setopt=install_weak_deps=False --best \
    ca-certificates \
    dbus-x11 \
    docker-ce \
    docker-ce-cli \
    glibc-all-langpacks \
    glibc-locale-source \
    google-noto-emoji-fonts \
    google-noto-sans-fonts \
    intel-media-driver \
    mesa-dri-drivers \
    mesa-libgbm \
    mesa-libGL \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    openbox \
    openssh-clients \
    openssl \
    pavucontrol \
    pulseaudio \
    sudo \
    xorg-x11-drv-amdgpu \
    xorg-x11-drv-ati \
    xorg-x11-drv-intel \
    xorg-x11-drv-nouveau \
    xorg-x11-drv-qxl \
    xorgxrdp \
    xrdp \
    xterm && \
  VERSION=$(ls -1 /usr/lib64/ | \
    awk -F '-' '/pulse-/ {print $2; exit}') && \
  ldconfig -n /usr/lib64/pulse-${VERSION}/modules && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    -e 's/NLIMC/NLMC/g' \
    -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
    -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** user perms ****" && \
  echo "abc:abc" | chpasswd && \
  usermod -s /bin/bash abc && \
  echo '%wheel ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/wheel && \
  usermod -G wheel abc && \
  echo "**** proot-apps ****" && \
  mkdir /proot-apps/ && \
  PAPPS_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/proot-apps/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  curl -L https://github.com/linuxserver/proot-apps/releases/download/${PAPPS_RELEASE}/proot-apps-x86_64.tar.gz \
    | tar -xzf - -C /proot-apps/ && \
  echo "${PAPPS_RELEASE}" > /proot-apps/pversion && \
  echo "**** configure locale ****" && \
  for LOCALE in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs); do \
    localedef -i $LOCALE -f UTF-8 $LOCALE.UTF-8; \
  done && \
  echo "**** theme ****" && \
  curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
    | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/ && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3389
VOLUME /config
