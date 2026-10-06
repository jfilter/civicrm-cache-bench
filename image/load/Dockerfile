# Load generators: oha for single requests, bench/flow.py (Python standard library) for request sequences.
FROM ghcr.io/hatoo/oha@sha256:3ec3dbf549ea197793482d47a6324797411406bbf438c2fe8b91f244ec641a2f AS oha

# python:3.13-slim
FROM python@sha256:bf44cdfcb76cd3b41e879bc058fc37ec5872002ccfde7fcb765e218cde0cd79c
COPY --from=oha /usr/bin/oha /usr/local/bin/oha
