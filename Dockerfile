FROM node:22-slim

# 1. System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client build-essential python3 python3-pip \
    g++ make ca-certificates curl && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages

# 2. Install pre-compiled OpenClaw globally from npm
RUN npm install -g openclaw@latest --unsafe-perm

# 3. Working directory and scripts
WORKDIR /app
COPY sync.py .
COPY start-openclaw.sh .
RUN chmod +x start-openclaw.sh

# 4. Environment & Port
ENV PORT=10000 HOME=/root
EXPOSE 10000

CMD ["./start-openclaw.sh"]
