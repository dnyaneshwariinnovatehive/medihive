FROM python:3.11-slim

# Install system dependencies for Pillow and psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg62-turbo \
    libwebp7 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir gunicorn[gevent]

# Copy application code
COPY backend/ .

# Create necessary directories
RUN mkdir -p /tmp/medihive_images

# Cloud Run provides PORT env var (default 8080)
EXPOSE 8080

# Health check endpoint for Cloud Run
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT:-8080}/api/health')" || exit 1

# Run with gunicorn - gevent worker for async performance
# Environment variable PORT is set by Cloud Run (default 8080)
CMD gunicorn --worker-class gevent \
    --workers 2 \
    --bind 0.0.0.0:${PORT:-8080} \
    --timeout 120 \
    --keep-alive 5 \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    app:app
