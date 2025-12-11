FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install LibreOffice, Python, UNO bindings, and Fonts
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-uno \
    libreoffice \
    default-jre \
    fonts-noto \
    fonts-liberation \
    fonts-dejavu \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Install Unoserver
# We use --break-system-packages because we MUST install into the system python
# environment to access the 'uno' library installed by apt.
RUN pip3 install --break-system-packages unoserver

# Create user
RUN groupadd -g "${GID}" worker && \
    useradd --create-home --no-log-init -u "${UID}" -g "${GID}" worker

USER worker
WORKDIR /home/worker

EXPOSE 2003
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["unoserver", "--interface", "0.0.0.0", "--conversion-timeout", "10"]