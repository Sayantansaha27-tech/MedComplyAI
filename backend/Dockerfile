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
