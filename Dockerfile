FROM node:22-slim

# 1. System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client build-essential python3 python3-pip \
    g++ make ca-certificates curl && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages

# 2. Install OpenClaw
RUN npm install -g openclaw@latest --unsafe-perm

# 3. Workdir & Entrypoint
WORKDIR /app
COPY sync.py .
COPY start-openclaw.sh .
RUN chmod +x start-openclaw.sh

# 4. Port Configuration (Render dynamically assigns PORT)
ENV PORT=10000 HOME=/root
EXPOSE 10000

CMD ["./start-openclaw.sh"]
