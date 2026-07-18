FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./

RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.txt

FROM base AS model-builder

RUN python -m pip install \
    --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

COPY download_models.sh ./

RUN sed -i 's/\r$//' download_models.sh \
    && chmod +x download_models.sh

RUN NC_TRANSLATION_MODEL_ROOT=/artifacts/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/artifacts/tokenizers \
    PYTHON_BIN=python \
    ./download_models.sh


# ------------------------------------------------------------
# Финальный runtime-образ
# ------------------------------------------------------------
FROM base AS runtime

ENV NC_TRANSLATION_HOST=0.0.0.0 \
    NC_TRANSLATION_PORT=8090 \
    NC_TRANSLATION_MODEL_ROOT=/app/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/app/tokenizers \
    NC_TRANSLATION_GLOSSARY_PATH=/app/config/glossary.json

COPY app ./app
COPY config ./config

COPY --from=model-builder /artifacts/models ./models
COPY --from=model-builder /artifacts/tokenizers ./tokenizers

EXPOSE 8090

CMD ["sh", "-c", "exec uvicorn app.main:app --host \"${NC_TRANSLATION_HOST}\" --port \"${NC_TRANSLATION_PORT}\""]
