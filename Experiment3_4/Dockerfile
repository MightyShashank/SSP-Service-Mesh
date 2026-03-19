FROM python:3.10-slim

# Set working dir
WORKDIR /app

# Copy only requirements first (cache optimization)
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Copy full project
COPY . .

# Default command
ENTRYPOINT ["python", "analysis/analyze.py"]