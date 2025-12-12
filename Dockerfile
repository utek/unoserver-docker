FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
# bash: for the entrypoint script
# procps: for 'pgrep' used in cleanup
# python3-*: for the application
# libreoffice + fonts: the core engine
RUN apt-get update && apt-get install -y \
    bash \
    python3 \
    python3-pip \
    python3-uno \
    libreoffice \
    default-jre \
    fonts-noto \
    fonts-liberation \
    fonts-dejavu \
    netcat-traditional \
    curl \
    tini \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install unoserver (includes unoconvert for healthchecks)
RUN pip3 install --break-system-packages unoserver

# Setup user
RUN groupadd -g "${GID}" worker && \
    useradd --create-home --no-log-init -u "${UID}" -g "${GID}" worker

USER worker
WORKDIR /home/worker

# Copy script to the location we call in CMD
COPY --chown=worker:worker build-context/entrypoint.sh /home/worker/entrypoint.sh
RUN chmod +x /home/worker/entrypoint.sh

EXPOSE 2003
ENTRYPOINT ["/usr/bin/tini", "--"]

# Point to the exact path where we copied the file
CMD ["/home/worker/entrypoint.sh"]