FROM swift:6.4.1
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    libadwaita-1-dev libgtk-4-dev libgdk-pixbuf-2.0-dev libsqlite3-dev pkg-config \
    xvfb dbus-x11 scrot fonts-noto-cjk fonts-noto-color-emoji adwaita-icon-theme \
 && rm -rf /var/lib/apt/lists/*
# Swift 6.4.1 already includes xauth; keep xvfb-run usable if the base changes.
RUN command -v xauth >/dev/null || (apt-get update \
 && apt-get install -y --no-install-recommends xauth \
 && rm -rf /var/lib/apt/lists/*)
WORKDIR /work
