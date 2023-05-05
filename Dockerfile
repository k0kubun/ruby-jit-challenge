FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
  autoconf bison patch build-essential rustc libssl-dev libyaml-dev libreadline6-dev \
  zlib1g-dev libgmp-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev uuid-dev \
  ruby git libcapstone-dev \
  && rm -rf /var/lib/apt/lists/*

ENV RUBY_REVISION=f2c367734f847a7277f09c583a0476086313fdc9
RUN git clone --depth=1 https://github.com/ruby/ruby /ruby && cd /ruby && \
  git fetch origin $RUBY_REVISION && git reset --hard $RUBY_REVISION && \
  ./autogen.sh && \
  ./configure --disable-install-doc --prefix=/usr/local --enable-yjit --enable-rjit=disasm && \
  make -j8 && make install && apt-get remove -y ruby && rm -rf /ruby

RUN mkdir /app
WORKDIR /app
