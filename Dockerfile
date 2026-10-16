FROM debian:trixie-slim

ARG UID=1000
ARG GID=1000
# renovate: pypi: unoserver
ARG VERSION_UNOSERVER=3.7

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install LibreOffice, Python, UNO bindings, and Fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-uno \
    libreoffice-writer-nogui \
    libreoffice-uiconfig-writer \
    libreoffice-calc-nogui \
    libreoffice-impress-nogui \
    libreoffice-draw-nogui \
    fonts-noto \
    fonts-noto-cjk \
    fonts-liberation \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-dejavu \
    netcat-traditional \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Install Unoserver
# We use --break-system-packages because we MUST install into the system python
# environment to access the 'uno' library installed by apt.
RUN pip3 install --break-system-packages unoserver==${VERSION_UNOSERVER}

# Create user
RUN groupadd -g "${GID}" worker && \
    useradd --create-home --no-log-init -u "${UID}" -g "${GID}" worker

USER worker
WORKDIR /home/worker

EXPOSE 2003
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 CMD ["unoping"]
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["unoserver", "--interface", "0.0.0.0", "--port", "2003" ,"--conversion-timeout", "10"]
