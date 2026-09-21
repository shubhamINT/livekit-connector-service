# Runtime for the standalone Google Meet connector.
# Chrome and ChromeDriver are pinned to the same versions as the parent
# attendee image, and ChromeDriver is installed at /usr/local/bin/chromedriver,
# which is the default of ConnectorConfig.chrome_driver_path.
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        unzip \
        python3 \
        python3-pip \
        xvfb \
        xauth \
        xclip \
        x11-utils \
        x11-xkb-utils \
        fonts-liberation \
        libvulkan1 \
        xdg-utils \
        libasound2 \
        libasound2-plugins \
        alsa-utils \
        pulseaudio \
        pulseaudio-utils \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Chrome 134.0.6998.88, pinned to match ChromeDriver below.
# Primary: .deb from attendee mirror (same checksum as parent image).
# Fallback: Chrome-for-Testing zip from the same GCS bucket as ChromeDriver,
# which has a more reliable TLS chain. wget exit code 5 (SSL verification
# failure) is common inside Docker Desktop behind a proxy/VPN, so both paths
# use curl with retries.
ARG CHROME_VERSION=134.0.6998.88
RUN set -ex; \
    CHROME_DEB="google-chrome-stable_${CHROME_VERSION}-1_amd64.deb"; \
    CHROME_URL="https://build-assets.attendee.dev/google-chrome/pool/main/g/google-chrome-stable/${CHROME_DEB}"; \
    CHROME_SHA="df557edb3d24d8dcaff9557d80733b42afb6626685200d3f34a3b6f528065cad"; \
    CFT_URL="https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-linux64.zip"; \
    if curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 30 -o "${CHROME_DEB}" "${CHROME_URL}"; then \
      echo "${CHROME_SHA}  ${CHROME_DEB}" | sha256sum -c -; \
      apt-get update; \
      apt-get install -y --no-install-recommends "./${CHROME_DEB}"; \
      rm -rf "${CHROME_DEB}" /var/lib/apt/lists/*; \
    else \
      echo "WARNING: .deb download failed, falling back to Chrome-for-Testing zip"; \
      curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 30 -o /tmp/chrome-linux64.zip "${CFT_URL}"; \
      unzip -q /tmp/chrome-linux64.zip -d /opt; \
      ln -sf /opt/chrome-linux64/chrome /usr/bin/google-chrome; \
      ln -sf /opt/chrome-linux64/chrome /usr/bin/google-chrome-stable; \
      rm -f /tmp/chrome-linux64.zip; \
    fi; \
    google-chrome --version

# Matching ChromeDriver.
RUN set -ex; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 30 \
      -o chromedriver-linux64.zip https://storage.googleapis.com/chrome-for-testing-public/134.0.6998.88/linux64/chromedriver-linux64.zip; \
    echo "58df717d51484b9f3ac188af5231cdc77255daa72d0b2b86481bee54e398ce2f  chromedriver-linux64.zip" | sha256sum -c -; \
    unzip -q chromedriver-linux64.zip; \
    mv chromedriver-linux64/chromedriver /usr/local/bin/chromedriver; \
    chmod +x /usr/local/bin/chromedriver; \
    rm -rf chromedriver-linux64 chromedriver-linux64.zip

WORKDIR /app

# Dependencies first so that source edits do not invalidate the layer.
COPY pyproject.toml README.md ./
COPY src ./src
COPY agent_run.py control_run.py ./
RUN pip install --no-cache-dir .

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
# Strip CRLF in case the build context was checked out on Windows
# (prevents '/usr/bin/env: bash\r: No such file or directory').
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh && chmod +x /usr/local/bin/docker-entrypoint.sh

# Chrome refuses to run as root without a sandbox opt-out; run as a normal user.
RUN useradd --create-home --uid 1000 app && chown -R app:app /app
USER app

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["python3", "-m", "livekit.agents", "start", "agent_run.py"]
