FROM swift:6.4.1
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
