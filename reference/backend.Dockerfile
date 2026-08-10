# ============================================================
# Reference only. Not runnable from this repository.
#
# In the private source repo this file lives at backend/Dockerfile
# and is built with the repo root as context:
#
#   build:
#     context: .
#     dockerfile: backend/Dockerfile
#
# The COPY paths below are relative to that root and are correct for
# it. They are deliberately left unchanged: rewriting them to resolve
# against this documentation repo would break the real build.
# ============================================================

FROM python:3.10-slim

WORKDIR /app

# System dependencies for PDF processing and OCR
RUN apt-get update && apt-get install -y \
    poppler-utils \
    libmagic1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (layer caching)
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Download NLTK data
RUN python -c "import nltk; nltk.download('punkt'); nltk.download('stopwords')"

# Copy application source
COPY backend/app ./app

# Storage directories
RUN mkdir -p /app/storage/documents \
    /app/storage/gap_documents \
    /app/storage/regulatory/parsed \
    /app/storage/reg_ingest_snapshots \
    /app/storage/gap_runs

EXPOSE 8000

CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
