# ====================================================================
# Resource Manager Dockerfile
# ====================================================================
# Automated resource monitoring and management service
# Uses Python 3.11 for Prometheus integration and Docker API

FROM python:3.11-slim

# ====================================================================
# METADATA
# ====================================================================
LABEL maintainer="Jacker Team"
LABEL description="Automated resource monitoring and management service"
LABEL version="1.0.0"

# ====================================================================
# ENVIRONMENT VARIABLES
# ====================================================================
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ====================================================================
# SYSTEM DEPENDENCIES
# ====================================================================
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        procps \
    && rm -rf /var/lib/apt/lists/*

# ====================================================================
# PYTHON DEPENDENCIES
# ====================================================================
WORKDIR /app

# Install Python packages
RUN pip install --no-cache-dir \
    prometheus-api-client==0.5.3 \
    docker==7.0.0 \
    pyyaml==6.0.1 \
    requests==2.31.0

# ====================================================================
# APPLICATION FILES
# ====================================================================
# Copy application files
COPY manager.py /app/manager.py

# Make script executable
RUN chmod +x /app/manager.py

# ====================================================================
# RUNTIME CONFIGURATION
# ====================================================================
# Create necessary directories
RUN mkdir -p /logs /config /tmp

# Health check script
RUN echo '#!/bin/sh\ncurl -f http://localhost:8000/health || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# ====================================================================
# USER AND PERMISSIONS
# ====================================================================
# Create non-root user for running the application
RUN useradd -r -u 1000 -g root -s /bin/bash -m resourcemgr && \
    chown -R resourcemgr:root /app /logs /config /tmp && \
    chmod -R 755 /app && \
    chmod -R 777 /tmp

# Switch to non-root user
USER resourcemgr

# ====================================================================
# EXPOSE PORTS
# ====================================================================
# Health and metrics endpoint
EXPOSE 8000

# ====================================================================
# ENTRYPOINT
# ====================================================================
ENTRYPOINT ["python", "/app/manager.py"]
