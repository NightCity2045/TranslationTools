# syntax=docker/dockerfile:1.7

# ============================================================
# Общий базовый образ
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

WORKDIR /opt/nc-translation

COPY requirements.txt /opt/nc-translation/requirements.txt

RUN python -m pip install --upgrade pip \
    && python -m pip install \
        --no-cache-dir \
        -r /opt/nc-translation/requirements.txt


# ============================================================
# Скачивание и конвертация моделей
# ============================================================
FROM base AS model-builder

# PyTorch нужен только для ct2-transformers-converter.
RUN python -m pip install \
    --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

COPY download_models.sh /opt/nc-translation/download_models.sh

RUN sed -i 's/\r$//' /opt/nc-translation/download_models.sh \
    && chmod +x /opt/nc-translation/download_models.sh

# Скрипт автоматически:
# - скачивает Helsinki-NLP/opus-mt-en-ru;
# - скачивает Helsinki-NLP/opus-mt-ru-en;
# - конвертирует модели в CTranslate2 int8;
# - сохраняет tokenizer-файлы.
RUN NC_TRANSLATION_MODEL_ROOT=/build-assets/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/build-assets/tokenizers \
    PYTHON_BIN=python \
    /opt/nc-translation/download_models.sh

# Строгая проверка результата скачивания и конвертации.
RUN set -eux; \
    test -s /build-assets/models/opus-mt-en-ru/model.bin; \
    test -s /build-assets/models/opus-mt-en-ru/config.json; \
    test -s /build-assets/models/opus-mt-ru-en/model.bin; \
    test -s /build-assets/models/opus-mt-ru-en/config.json; \
    test -d /build-assets/tokenizers/opus-mt-en-ru; \
    test -n "$(find /build-assets/tokenizers/opus-mt-en-ru -type f -print -quit)"; \
    test -d /build-assets/tokenizers/opus-mt-ru-en; \
    test -n "$(find /build-assets/tokenizers/opus-mt-ru-en -type f -print -quit)"; \
    echo "All translation models and tokenizers were built successfully."


# ============================================================
# Финальный образ
# ============================================================
FROM base AS runtime

ENV NC_TRANSLATION_HOST=0.0.0.0 \
    NC_TRANSLATION_PORT=8090 \
    NC_TRANSLATION_MODEL_ROOT=/var/lib/nc-translation/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/var/lib/nc-translation/tokenizers \
    NC_TRANSLATION_GLOSSARY_PATH=/etc/nc-translation/glossary.json

# Код приложения больше не находится в /app.
COPY app /opt/nc-translation/app

# Стандартная конфигурация и пример glossary.
COPY config /etc/nc-translation

# Резервная неизменяемая копия моделей внутри образа.
COPY --from=model-builder \
    /build-assets/models \
    /usr/local/share/nc-translation/models

COPY --from=model-builder \
    /build-assets/tokenizers \
    /usr/local/share/nc-translation/tokenizers

COPY docker-entrypoint.sh /usr/local/bin/nc-translation-entrypoint

RUN sed -i 's/\r$//' /usr/local/bin/nc-translation-entrypoint \
    && chmod +x /usr/local/bin/nc-translation-entrypoint \
    && mkdir -p \
        /var/lib/nc-translation/models \
        /var/lib/nc-translation/tokenizers \
    && cp -a \
        /usr/local/share/nc-translation/models/. \
        /var/lib/nc-translation/models/ \
    && cp -a \
        /usr/local/share/nc-translation/tokenizers/. \
        /var/lib/nc-translation/tokenizers/

# Проверка уже финального runtime-образа.
RUN set -eux; \
    test -s /var/lib/nc-translation/models/opus-mt-en-ru/model.bin; \
    test -s /var/lib/nc-translation/models/opus-mt-en-ru/config.json; \
    test -s /var/lib/nc-translation/models/opus-mt-ru-en/model.bin; \
    test -s /var/lib/nc-translation/models/opus-mt-ru-en/config.json; \
    test -d /var/lib/nc-translation/tokenizers/opus-mt-en-ru; \
    test -n "$(find /var/lib/nc-translation/tokenizers/opus-mt-en-ru -type f -print -quit)"; \
    test -d /var/lib/nc-translation/tokenizers/opus-mt-ru-en; \
    test -n "$(find /var/lib/nc-translation/tokenizers/opus-mt-ru-en -type f -print -quit)"; \
    echo "Runtime translation assets are valid."

EXPOSE 8090

ENTRYPOINT ["/usr/local/bin/nc-translation-entrypoint"]

CMD ["sh", "-c", "exec uvicorn app.main:app --host \"${NC_TRANSLATION_HOST}\" --port \"${NC_TRANSLATION_PORT}\""]
