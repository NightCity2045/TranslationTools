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

COPY requirements.txt /app/requirements.txt

RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir -r /app/requirements.txt


# ------------------------------------------------------------
# Скачивание и конвертация моделей
# ------------------------------------------------------------
FROM base AS model-builder

RUN python -m pip install \
    --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

COPY download_models.sh /app/download_models.sh

RUN sed -i 's/\r$//' /app/download_models.sh \
    && chmod +x /app/download_models.sh

RUN NC_TRANSLATION_MODEL_ROOT=/artifacts/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/artifacts/tokenizers \
    PYTHON_BIN=python \
    /app/download_models.sh \
    && test -s /artifacts/models/opus-mt-en-ru/model.bin \
    && test -s /artifacts/models/opus-mt-en-ru/config.json \
    && test -s /artifacts/models/opus-mt-ru-en/model.bin \
    && test -s /artifacts/models/opus-mt-ru-en/config.json \
    && test -d /artifacts/tokenizers/opus-mt-en-ru \
    && test -n "$(find /artifacts/tokenizers/opus-mt-en-ru -type f -print -quit)" \
    && test -d /artifacts/tokenizers/opus-mt-ru-en \
    && test -n "$(find /artifacts/tokenizers/opus-mt-ru-en -type f -print -quit)"


# ------------------------------------------------------------
# Финальный runtime-образ
# ------------------------------------------------------------
FROM base AS runtime

ENV NC_TRANSLATION_HOST=0.0.0.0 \
    NC_TRANSLATION_PORT=8090 \
    NC_TRANSLATION_MODEL_ROOT=/app/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/app/tokenizers \
    NC_TRANSLATION_GLOSSARY_PATH=/app/config/glossary.json

COPY app /app/app
COPY config /app/config

COPY --from=model-builder /artifacts/models /app/models
COPY --from=model-builder /artifacts/tokenizers /app/tokenizers

RUN test -s /app/models/opus-mt-en-ru/model.bin \
    && test -s /app/models/opus-mt-en-ru/config.json \
    && test -s /app/models/opus-mt-ru-en/model.bin \
    && test -s /app/models/opus-mt-ru-en/config.json \
    && test -d /app/tokenizers/opus-mt-en-ru \
    && test -n "$(find /app/tokenizers/opus-mt-en-ru -type f -print -quit)" \
    && test -d /app/tokenizers/opus-mt-ru-en \
    && test -n "$(find /app/tokenizers/opus-mt-ru-en -type f -print -quit)"

EXPOSE 8090

CMD ["sh", "-c", "exec uvicorn app.main:app --host \"${NC_TRANSLATION_HOST}\" --port \"${NC_TRANSLATION_PORT}\""]
