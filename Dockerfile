FROM ubuntu:20.04 as build-dep

# Use bash for the shell
SHELL ["bash", "-c"]

# Install Node v12 (LTS)
ENV NODE_VER="12.16.3"
RUN ARCH= && \
    dpkgArch="$(dpkg --print-architecture)" && \
  case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac && \
    echo "Etc/UTC" > /etc/localtime && \
	apt update && \
	apt -y install wget python && \
	cd ~ && \
	wget https://nodejs.org/download/release/v$NODE_VER/node-v$NODE_VER-linux-$ARCH.tar.gz && \
	tar xf node-v$NODE_VER-linux-$ARCH.tar.gz && \
	rm node-v$NODE_VER-linux-$ARCH.tar.gz && \
	mv node-v$NODE_VER-linux-$ARCH /opt/node

# Install jemalloc
ENV JE_VER="5.2.1"
RUN apt update && \
	apt -y install make autoconf gcc g++ && \
	cd ~ && \
	wget https://github.com/jemalloc/jemalloc/archive/$JE_VER.tar.gz && \
	tar xf $JE_VER.tar.gz && \
	cd jemalloc-$JE_VER && \
	./autogen.sh && \
	./configure --prefix=/opt/jemalloc && \
	make -j$(nproc) > /dev/null && \
	make install_bin install_include install_lib && \
	cd .. && rm -rf jemalloc-$JE_VER $JE_VER.tar.gz

# Install Ruby
ENV RUBY_VER="2.6.6"
ENV CPPFLAGS="-I/opt/jemalloc/include"
ENV LDFLAGS="-L/opt/jemalloc/lib/"
RUN apt update && \
	apt -y install build-essential \
		bison libyaml-dev libgdbm-dev libreadline-dev \
		libncurses5-dev libffi-dev zlib1g-dev libssl-dev && \
	cd ~ && \
	wget https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz && \
	tar xf ruby-$RUBY_VER.tar.gz && \
	cd ruby-$RUBY_VER && \
	./configure --prefix=/opt/ruby \
	  --with-jemalloc \
	  --with-shared \
	  --disable-install-doc && \
	ln -s /opt/jemalloc/lib/* /usr/lib/ && \
	make -j$(nproc) > /dev/null && \
	make install && \
	cd .. && rm -rf ruby-$RUBY_VER.tar.gz ruby-$RUBY_VER

ENV PATH="/opt/ruby/bin:/opt/node/bin:${PATH}"

RUN npm install -g yarn && \
	apt update && \
	apt -y install git libicu-dev libidn11-dev \
	libpq-dev libprotobuf-dev protobuf-compiler

RUN gem install --install-dir /opt/ruby/lib/ruby/site_ruby/2.6.0 bundler

COPY Gemfile* package.json yarn.lock /opt/mastodon/

RUN cd /opt/mastodon && \
  bundle config set deployment 'true' && \
  bundle config set without 'development test' && \
	bundle install -j$(nproc) && \
	yarn install --pure-lockfile

FROM ubuntu:20.04

# Copy over all the langs needed for runtime
COPY --from=build-dep /opt/node /opt/node
COPY --from=build-dep /opt/ruby /opt/ruby
COPY --from=build-dep /opt/jemalloc /opt/jemalloc

# Add more PATHs to the PATH
ENV PATH="/opt/mastodon/bin:/opt/ruby/bin:/opt/node/bin:${PATH}"

# Create the mastodon user
ARG UID=991
ARG GID=991
RUN apt update && \
	echo "Etc/UTC" > /etc/localtime && \
	ln -s /opt/jemalloc/lib/* /usr/lib/ && \
	apt install -y whois wget && \
	addgroup --gid $GID mastodon && \
	useradd -m -u $UID -g $GID -d /opt/mastodon mastodon && \
	echo "mastodon:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 | mkpasswd -s -m sha-256`" | chpasswd

# Install mastodon runtime deps
RUN apt -y --no-install-recommends install \
        libssl1.1 libpq5 imagemagick ffmpeg webp \
	libicu66 libprotobuf17 libidn11 libyaml-0-2 \
	file ca-certificates tzdata libreadline8 && \
	apt -y install gcc && \
	ln -s /opt/mastodon /mastodon && \
	gem install bundler && \
	rm -rf /var/cache && \
	rm -rf /var/lib/apt/lists/*

# Add tini
ENV TINI_VERSION="0.19.0"
RUN dpkgArch="$(dpkg --print-architecture)" && \
	ARCH=$dpkgArch && \
	wget https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$ARCH \
	https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$ARCH.sha256sum && \
	cat tini-$ARCH.sha256sum | sha256sum -c - && \
	mv tini-$ARCH /tini && rm tini-$ARCH.sha256sum && \
	chmod +x /tini

# Copy over mastodon source, and dependencies from building, and set permissions
COPY --chown=mastodon:mastodon . /opt/mastodon
COPY --from=build-dep --chown=mastodon:mastodon /opt/mastodon /opt/mastodon

# Run mastodon services in prod mode
ENV RAILS_ENV="production"
ENV NODE_ENV="production"

# Tell rails to serve static files
ENV RAILS_SERVE_STATIC_FILES="true"
ENV BIND="0.0.0.0"

# Set the run user
USER mastodon

# Precompile assets
#RUN cd ~ && \
#	OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile && \
#	yarn cache clean

# Set the work dir and the container entry point
WORKDIR /opt/mastodon
ENTRYPOINT ["/tini", "--"]
EXPOSE 3000 4000
