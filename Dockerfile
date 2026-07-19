# syntax=docker/dockerfile:1.7

# ============================================================
# Базовый образ
# ============================================================
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt /app/requirements.txt

RUN python -m pip install --upgrade pip \
    && python -m pip install \
        --no-cache-dir \
        -r /app/requirements.txt


# ============================================================
# Скачивание и конвертация моделей
# ============================================================
FROM base AS model-builder

# PyTorch требуется только для конвертации моделей.
# В финальный образ он не попадёт.
RUN python -m pip install \
    --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

COPY download_models.sh /app/download_models.sh

RUN sed -i 's/\r$//' /app/download_models.sh \
    && chmod +x /app/download_models.sh

RUN NC_TRANSLATION_MODEL_ROOT=/build-assets/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/build-assets/tokenizers \
    PYTHON_BIN=python \
    /app/download_models.sh

# Проверяем обе модели и оба tokenizer-набора.
RUN set -eux; \
    test -s /build-assets/models/opus-mt-en-ru/model.bin; \
    test -s /build-assets/models/opus-mt-en-ru/config.json; \
    test -s /build-assets/models/opus-mt-ru-en/model.bin; \
    test -s /build-assets/models/opus-mt-ru-en/config.json; \
    test -s /build-assets/tokenizers/opus-mt-en-ru/tokenizer_config.json; \
    test -s /build-assets/tokenizers/opus-mt-ru-en/tokenizer_config.json; \
    test -n "$(find /build-assets/tokenizers/opus-mt-en-ru -type f -print -quit)"; \
    test -n "$(find /build-assets/tokenizers/opus-mt-ru-en -type f -print -quit)"; \
    echo "Translation models were built successfully."


# ============================================================
# Финальный runtime-образ
# ============================================================
FROM base AS runtime

ENV NC_TRANSLATION_HOST=0.0.0.0 \
    NC_TRANSLATION_PORT=8090 \
    NC_TRANSLATION_MODEL_ROOT=/app/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/app/tokenizers \
    NC_TRANSLATION_GLOSSARY_PATH=/app/config/glossary.json

WORKDIR /app

COPY app /app/app
COPY config /app/config

# Модели хранятся в защищённом каталоге, который не перекрывается
# volumes из docker-compose.yml.
COPY --from=model-builder \
    /build-assets/models \
    /opt/nc-translation-seed/models

COPY --from=model-builder \
    /build-assets/tokenizers \
    /opt/nc-translation-seed/tokenizers

COPY docker-entrypoint.sh /usr/local/bin/nc-translation-entrypoint

RUN sed -i 's/\r$//' /usr/local/bin/nc-translation-entrypoint \
    && chmod +x /usr/local/bin/nc-translation-entrypoint \
    && mkdir -p /app/models /app/tokenizers

# Проверяем резервные модели внутри финального образа.
RUN set -eux; \
    test -s /opt/nc-translation-seed/models/opus-mt-en-ru/model.bin; \
    test -s /opt/nc-translation-seed/models/opus-mt-en-ru/config.json; \
    test -s /opt/nc-translation-seed/models/opus-mt-ru-en/model.bin; \
    test -s /opt/nc-translation-seed/models/opus-mt-ru-en/config.json; \
    test -s /opt/nc-translation-seed/tokenizers/opus-mt-en-ru/tokenizer_config.json; \
    test -s /opt/nc-translation-seed/tokenizers/opus-mt-ru-en/tokenizer_config.json; \
    echo "Runtime seed assets are valid."

EXPOSE 8090

ENTRYPOINT ["/usr/local/bin/nc-translation-entrypoint"]

CMD ["sh", "-c", "exec uvicorn app.main:app --host \"${NC_TRANSLATION_HOST}\" --port \"${NC_TRANSLATION_PORT}\""]
