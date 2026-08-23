FROM python:3.12-slim

WORKDIR /app
COPY python/requirements.txt /app/python/requirements.txt
RUN pip install --no-cache-dir -r /app/python/requirements.txt
COPY python /app/python

ENV PYTHONUNBUFFERED=1
ENV NEOFL_REASONER=auto
ENV NEOFL_OLLAMA_URL=http://host.docker.internal:11434
ENV NEOFL_REASONING_MODEL=qwen3:8b

EXPOSE 8787

CMD ["sh", "-c", "python /app/python/run_gateway.py --host 0.0.0.0 --port 8787 --token \"$NEOFL_GATEWAY_TOKEN\""]
