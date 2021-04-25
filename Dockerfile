FROM ghcr.io/linuxserver/baseimage-ubuntu:focal as buildstage

ARG XRDP_PULSE_VERSION=v0.4

RUN \
 echo "**** install build deps ****" && \
 sed -i 's/# deb-src/deb-src/g' /etc/apt/sources.list && \
 apt-get update && \
 apt-get install -y \
	build-essential \
	devscripts \
	dpkg-dev \
	git \
	libpulse-dev \
	pulseaudio && \
 apt build-dep -y \
	pulseaudio \
	xrdp

RUN \
 echo "**** build pulseaudio modules ****" && \
 mkdir -p /buildout/var/lib/xrdp-pulseaudio-installer && \
 tmp=$(mktemp -d); cd "$tmp" && \
 pulseaudio_version=$(dpkg-query -W -f='${source:Version}' pulseaudio|awk -F: '{print $2}') && \
 pulseaudio_upstream_version=$(dpkg-query -W -f='${source:Upstream-Version}' pulseaudio) && \
 set -- $(apt-cache policy pulseaudio | fgrep -A1 '***' | tail -1) && \
 mirror=$2 && \
 suite=${3#*/} && \
 dget -u "$mirror/pool/$suite/p/pulseaudio/pulseaudio_$pulseaudio_version.dsc" && \
 cd "pulseaudio-$pulseaudio_upstream_version" && \
 ./configure && \
 cd - && \
 git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git && \
 cd pulseaudio-module-xrdp && \
 git checkout ${XRDP_PULSE_VERSION} && \
 ./bootstrap && \
 ./configure PULSE_DIR="$tmp/pulseaudio-$pulseaudio_upstream_version" && \
 make && \
 install -t "/buildout/var/lib/xrdp-pulseaudio-installer" -D -m 644 src/.libs/*.so

RUN \
 echo "**** build xrdp with fuse disabled ****" && \
 cd /tmp && \
 apt-get source xrdp && \
 cd xrdp-* && \
 sed -i 's/--enable-fuse/--disable-fuse/g' debian/rules && \
 debuild -b -uc -us && \
 cp -ax ../xrdp_*.deb /buildout/xrdp.deb

# docker compose
FROM ghcr.io/linuxserver/docker-compose:amd64-latest as compose

# runtime stage
FROM ghcr.io/linuxserver/baseimage-ubuntu:focal

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# copy over libs and installers from build stage
COPY --from=buildstage /buildout/ /
COPY --from=compose /usr/local/bin/docker-compose /usr/local/bin/docker-compose

RUN \
 echo "**** install deps ****" && \
 ldconfig && \
 apt-get update && \
 DEBIAN_FRONTEND=noninteractive \
 apt-get install -y --no-install-recommends \
	apt-transport-https \
	ca-certificates \
	curl \
 	dbus-x11 \
	gawk \
	gnupg2 \
	libfuse2 \
	libx11-dev \
	libxfixes3 \
	libxml2 \
	libxrandr2 \
	openssh-client \
	pulseaudio \
	software-properties-common \
	sudo \
	x11-apps \
	x11-xserver-utils \
	xfonts-base \
	xorgxrdp \
	xrdp \
	xserver-xorg-core \
	xutils \
	zlib1g && \
 dpkg -i /xrdp.deb && \
 rm /xrdp.deb && \
 echo "**** install docker ****" && \
 curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
 add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable" && \
 apt-get update && \
 apt-get install -y --no-install-recommends \
	docker-ce-cli && \
 echo "**** cleanup and user perms ****" && \
 echo "abc:abc" | chpasswd && \
 usermod -aG sudo abc && \
 apt-get autoclean && \
 rm -rf \
	/var/lib/apt/lists/* \
	/var/tmp/* \
	/tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3389
VOLUME /config
