# syntax=docker/dockerfile:1.7

# ============================================================
# Общий базовый образ
# ============================================================
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

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip \
    && python -m pip install -r /app/requirements.txt


# ============================================================
# Скачивание и конвертация моделей
# ============================================================
FROM base AS model-builder

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install \
        --index-url https://download.pytorch.org/whl/cpu \
        torch

COPY download_models.sh /app/download_models.sh

RUN sed -i 's/\r$//' /app/download_models.sh \
    && chmod +x /app/download_models.sh

RUN --mount=type=cache,target=/root/.cache/huggingface \
    --mount=type=cache,target=/root/.cache/pip \
    NC_TRANSLATION_MODEL_ROOT=/build-assets/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/build-assets/tokenizers \
    NC_TRANSLATION_SKIP_PIP_INSTALL=1 \
    HF_HOME=/root/.cache/huggingface \
    PYTHON_BIN=python \
    /app/download_models.sh

# Docker-сборка не продолжится, если хотя бы одна модель повреждена.
RUN set -eux; \
    test -s /build-assets/models/opus-mt-en-ru/model.bin; \
    test -s /build-assets/models/opus-mt-en-ru/config.json; \
    test -s /build-assets/models/opus-mt-ru-en/model.bin; \
    test -s /build-assets/models/opus-mt-ru-en/config.json; \
    \
    test -s /build-assets/tokenizers/opus-mt-en-ru/tokenizer_config.json; \
    test -s /build-assets/tokenizers/opus-mt-ru-en/tokenizer_config.json; \
    \
    { \
        test -s /build-assets/tokenizers/opus-mt-en-ru/tokenizer.json \
        || { \
            test -s /build-assets/tokenizers/opus-mt-en-ru/source.spm; \
            test -s /build-assets/tokenizers/opus-mt-en-ru/target.spm; \
            test -s /build-assets/tokenizers/opus-mt-en-ru/vocab.json; \
        }; \
    }; \
    \
    { \
        test -s /build-assets/tokenizers/opus-mt-ru-en/tokenizer.json \
        || { \
            test -s /build-assets/tokenizers/opus-mt-ru-en/source.spm; \
            test -s /build-assets/tokenizers/opus-mt-ru-en/target.spm; \
            test -s /build-assets/tokenizers/opus-mt-ru-en/vocab.json; \
        }; \
    }; \
    \
    echo "Model builder assets passed validation."


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

# Неперекрываемая резервная копия моделей.
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

# Проверяем наличие entrypoint и резервных файлов прямо в образе.
RUN set -eux; \
    test -x /usr/local/bin/nc-translation-entrypoint; \
    \
    test -s /opt/nc-translation-seed/models/opus-mt-en-ru/model.bin; \
    test -s /opt/nc-translation-seed/models/opus-mt-en-ru/config.json; \
    test -s /opt/nc-translation-seed/models/opus-mt-ru-en/model.bin; \
    test -s /opt/nc-translation-seed/models/opus-mt-ru-en/config.json; \
    \
    test -s /opt/nc-translation-seed/tokenizers/opus-mt-en-ru/tokenizer_config.json; \
    test -s /opt/nc-translation-seed/tokenizers/opus-mt-ru-en/tokenizer_config.json

# Автоматический smoke-test entrypoint во время docker build.
#
# Здесь создаются искусственно пустые каталоги, после чего entrypoint
# обязан самостоятельно заполнить и проверить их.
RUN set -eux; \
    rm -rf /tmp/nc-translation-test; \
    \
    NC_TRANSLATION_MODEL_ROOT=/tmp/nc-translation-test/models \
    NC_TRANSLATION_TOKENIZER_ROOT=/tmp/nc-translation-test/tokenizers \
    /usr/local/bin/nc-translation-entrypoint true; \
    \
    test -s /tmp/nc-translation-test/models/opus-mt-en-ru/model.bin; \
    test -s /tmp/nc-translation-test/models/opus-mt-ru-en/model.bin; \
    test -s /tmp/nc-translation-test/tokenizers/opus-mt-en-ru/tokenizer_config.json; \
    test -s /tmp/nc-translation-test/tokenizers/opus-mt-ru-en/tokenizer_config.json; \
    \
    rm -rf /tmp/nc-translation-test; \
    echo "Entrypoint smoke test passed."

EXPOSE 8090

ENTRYPOINT ["/usr/local/bin/nc-translation-entrypoint"]

CMD ["sh", "-c", "exec uvicorn app.main:app --host \"${NC_TRANSLATION_HOST}\" --port \"${NC_TRANSLATION_PORT}\""]
