FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    unzip \
    jq \
    bash \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for restarting minecraft container)
RUN curl -fsSL https://get.docker.com | sh

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY app.py .
COPY scripts/install-mcaddon.sh .
COPY scripts/remove-mcaddon.sh .

# Make scripts executable
RUN chmod +x install-mcaddon.sh remove-mcaddon.sh

# Create upload directory
RUN mkdir -p /app/uploads

# Expose port
EXPOSE 8000

# Run the application
CMD ["python", "app.py"]