# syntax=docker/dockerfile:1
#
# Isolated Claude Code image with the academic-research-skills (ARS) plugin
# baked in at its newest release (or a chosen tag). Build with bin/ars-build, run with bin/ars.

FROM node:22-bookworm-slim

# Fail RUN steps when any command in a pipeline fails (curl | tar, git | sort).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ARS version to bake in: "latest" resolves to the newest vX.Y.Z release tag.
# Rebuild to upgrade (the in-session update check is disabled because the
# plugin directory is read-only).
ARG ARS_REPO=https://github.com/Imbad0202/academic-research-skills.git
ARG ARS_REF=latest
ARG CLAUDE_CODE_VERSION=latest
# Optional ARS output formats: Pandoc for DOCX, tectonic for APA 7.0 PDF.
ARG INSTALL_PANDOC=true
ARG INSTALL_TECTONIC=false
ARG TECTONIC_VERSION=0.15.0
# Optional native PDF content classifier (scripts/pdf_content_classifier_worker.py).
ARG INSTALL_PDF_CLASSIFIER=false
# Match the host user so files written to the mounted project are owned by you.
ARG UID=1000
ARG GID=1000

# bash, jq, curl and python3 are required by the ARS hooks and scripts;
# wget is for downloads Claude makes during a session.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git jq python3 python3-venv wget \
    && if [ "$INSTALL_PANDOC" = "true" ]; then \
        apt-get install -y --no-install-recommends pandoc; fi \
    && if [ "$INSTALL_TECTONIC" = "true" ]; then \
        apt-get install -y --no-install-recommends fonts-noto-cjk; fi \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$INSTALL_TECTONIC" = "true" ]; then \
        case "$(uname -m)" in \
            x86_64) arch=x86_64 ;; \
            aarch64) arch=aarch64 ;; \
            *) echo "tectonic: unsupported arch $(uname -m)" >&2; exit 1 ;; \
        esac \
        && curl -fsSL "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%40${TECTONIC_VERSION}/tectonic-${TECTONIC_VERSION}-${arch}-unknown-linux-musl.tar.gz" \
            | tar -xz -C /usr/local/bin tectonic; \
    fi

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force

RUN ref="$ARS_REF" \
    && if [ "$ref" = "latest" ]; then \
        ref="$(git ls-remote --tags --refs "$ARS_REPO" \
            | sed 's|.*refs/tags/||' | grep -E '^v[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1)" \
        && [ -n "$ref" ]; fi \
    && git clone --depth 1 --branch "$ref" "$ARS_REPO" /opt/ars \
    && rm -rf /opt/ars/.git \
    && echo "$ref" > /opt/ars/.ars-ref

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r /opt/ars/requirements-dev.txt \
    && if [ "$INSTALL_PDF_CLASSIFIER" = "true" ]; then \
        /opt/venv/bin/pip install --no-cache-dir -r /opt/ars/requirements-pdf-content-classifier.txt; fi

# The base image ships a "node" user at UID/GID 1000; replace it with ours.
# -o allows IDs that collide with system groups (e.g. macOS GID 20 "staff").
RUN userdel -r node \
    && groupadd -o -g "$GID" claude \
    && useradd -o -m -u "$UID" -g "$GID" -s /bin/bash claude

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    DISABLE_AUTOUPDATER=1 \
    ARS_UPDATE_CHECK=0

LABEL org.opencontainers.image.title="ars-sandbox" \
      org.opencontainers.image.description="Claude Code with academic-research-skills"

USER claude
WORKDIR /work

ENTRYPOINT ["claude", "--plugin-dir", "/opt/ars"]
