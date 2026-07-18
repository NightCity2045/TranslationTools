#!/usr/bin/env bash
set -euo pipefail

MODEL_ROOT="${NC_TRANSLATION_MODEL_ROOT:-/var/lib/nc-translation/models}"
TOKENIZER_ROOT="${NC_TRANSLATION_TOKENIZER_ROOT:-/var/lib/nc-translation/tokenizers}"

BUNDLED_MODEL_ROOT="/usr/local/share/nc-translation/models"
BUNDLED_TOKENIZER_ROOT="/usr/local/share/nc-translation/tokenizers"

MODEL_NAMES=(
    "opus-mt-en-ru"
    "opus-mt-ru-en"
)

log() {
    printf '[nc-translation-entrypoint] %s\n' "$*"
}

model_is_valid() {
    local model_name="$1"
    local model_dir="$MODEL_ROOT/$model_name"

    test -d "$model_dir" \
        && test -s "$model_dir/model.bin" \
        && test -s "$model_dir/config.json"
}

bundled_model_is_valid() {
    local model_name="$1"
    local model_dir="$BUNDLED_MODEL_ROOT/$model_name"

    test -d "$model_dir" \
        && test -s "$model_dir/model.bin" \
        && test -s "$model_dir/config.json"
}

tokenizer_is_valid() {
    local tokenizer_name="$1"
    local tokenizer_dir="$TOKENIZER_ROOT/$tokenizer_name"

    test -d "$tokenizer_dir" \
        && test -n "$(find "$tokenizer_dir" -type f -print -quit 2>/dev/null)"
}

bundled_tokenizer_is_valid() {
    local tokenizer_name="$1"
    local tokenizer_dir="$BUNDLED_TOKENIZER_ROOT/$tokenizer_name"

    test -d "$tokenizer_dir" \
        && test -n "$(find "$tokenizer_dir" -type f -print -quit 2>/dev/null)"
}

restore_model() {
    local model_name="$1"
    local source_dir="$BUNDLED_MODEL_ROOT/$model_name"
    local target_dir="$MODEL_ROOT/$model_name"

    if ! bundled_model_is_valid "$model_name"; then
        log "ERROR: bundled model is missing or damaged: $source_dir"
        return 1
    fi

    log "Restoring model: $model_name"

    rm -rf "$target_dir"
    mkdir -p "$target_dir"

    cp -a "$source_dir/." "$target_dir/"
}

restore_tokenizer() {
    local tokenizer_name="$1"
    local source_dir="$BUNDLED_TOKENIZER_ROOT/$tokenizer_name"
    local target_dir="$TOKENIZER_ROOT/$tokenizer_name"

    if ! bundled_tokenizer_is_valid "$tokenizer_name"; then
        log "ERROR: bundled tokenizer is missing or damaged: $source_dir"
        return 1
    fi

    log "Restoring tokenizer: $tokenizer_name"

    rm -rf "$target_dir"
    mkdir -p "$target_dir"

    cp -a "$source_dir/." "$target_dir/"
}

mkdir -p "$MODEL_ROOT"
mkdir -p "$TOKENIZER_ROOT"

log "Checking translation assets..."
log "Model root: $MODEL_ROOT"
log "Tokenizer root: $TOKENIZER_ROOT"

for model_name in "${MODEL_NAMES[@]}"; do
    if model_is_valid "$model_name"; then
        log "Model OK: $model_name"
    else
        log "Model missing or incomplete: $model_name"
        restore_model "$model_name"
    fi

    if tokenizer_is_valid "$model_name"; then
        log "Tokenizer OK: $model_name"
    else
        log "Tokenizer missing or incomplete: $model_name"
        restore_tokenizer "$model_name"
    fi
done

for model_name in "${MODEL_NAMES[@]}"; do
    if ! model_is_valid "$model_name"; then
        log "ERROR: model validation failed after recovery: $model_name"
        exit 1
    fi

    if ! tokenizer_is_valid "$model_name"; then
        log "ERROR: tokenizer validation failed after recovery: $model_name"
        exit 1
    fi
done

log "All translation assets are ready."
log "Starting NC Translation Service..."

exec "$@"
