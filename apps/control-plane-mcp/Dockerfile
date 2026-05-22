# Multi-stage optional; keep single stage for small image and Kind pulls.
FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir --upgrade pip

COPY pyproject.toml README.md ./
COPY src ./src

RUN pip install --no-cache-dir .

ENV PYTHONUNBUFFERED=1 \
    HOST=0.0.0.0 \
    PORT=8000 \
    CONTROL_PLANE_URL=http://127.0.0.1:3000 \
    FASTMCP_SHOW_BANNER=false

EXPOSE 8000

ENTRYPOINT ["python", "-m", "spice_control_plane_mcp"]
