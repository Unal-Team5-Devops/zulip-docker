FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
ARG PIP_FIND_LINKS
ARG PIP_NO_INDEX=0
ARG PIP_TRUSTED_HOST
RUN pip install --timeout 120 --retries 5 --no-cache-dir -r requirements.txt && mkdir /events && chown 65534:65534 /events
COPY collector.py receiver.py ./
USER 65534:65534
CMD ["python", "collector.py"]
