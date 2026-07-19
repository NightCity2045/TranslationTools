#!/usr/bin/env bash
set -euo pipefail

MODEL_ROOT="${NC_TRANSLATION_MODEL_ROOT:-/app/models}"
TOKENIZER_ROOT="${NC_TRANSLATION_TOKENIZER_ROOT:-/app/tokenizers}"

SEED_MODEL_ROOT="/opt/nc-translation-seed/models"
SEED_TOKENIZER_ROOT="/opt/nc-translation-seed/tokenizers"

MODEL_NAMES=(
    "opus-mt-en-ru"
    "opus-mt-ru-en"
)

log() {
    printf '[nc-translation] %s\n' "$*"
}

model_is_valid() {
    local name="$1"
    local directory="$MODEL_ROOT/$name"

    test -d "$directory" \
        && test -s "$directory/model.bin" \
        && test -s "$directory/config.json"
}

seed_model_is_valid() {
    local name="$1"
    local directory="$SEED_MODEL_ROOT/$name"

    test -d "$directory" \
        && test -s "$directory/model.bin" \
        && test -s "$directory/config.json"
}

tokenizer_is_valid() {
    local name="$1"
    local directory="$TOKENIZER_ROOT/$name"

    test -d "$directory" \
        && test -s "$directory/tokenizer_config.json" \
        && test -n "$(find "$directory" -type f -print -quit 2>/dev/null)"
}

seed_tokenizer_is_valid() {
    local name="$1"
    local directory="$SEED_TOKENIZER_ROOT/$name"

    test -d "$directory" \
        && test -s "$directory/tokenizer_config.json" \
        && test -n "$(find "$directory" -type f -print -quit 2>/dev/null)"
}

restore_model() {
    local name="$1"
    local source="$SEED_MODEL_ROOT/$name"
    local destination="$MODEL_ROOT/$name"

    if ! seed_model_is_valid "$name"; then
        log "ERROR: seed model is missing or damaged: $source"
        exit 3
    fi

    log "Restoring model $name into persistent volume..."

    rm -rf "$destination"
    mkdir -p "$destination"
    cp -a "$source/." "$destination/"
}

restore_tokenizer() {
    local name="$1"
    local source="$SEED_TOKENIZER_ROOT/$name"
    local destination="$TOKENIZER_ROOT/$name"

    if ! seed_tokenizer_is_valid "$name"; then
        log "ERROR: seed tokenizer is missing or damaged: $source"
        exit 3
    fi

    log "Restoring tokenizer $name into persistent volume..."

    rm -rf "$destination"
    mkdir -p "$destination"
    cp -a "$source/." "$destination/"
}

mkdir -p "$MODEL_ROOT"
mkdir -p "$TOKENIZER_ROOT"

log "Checking translation assets..."
log "Model root: $MODEL_ROOT"
log "Tokenizer root: $TOKENIZER_ROOT"

for name in "${MODEL_NAMES[@]}"; do
    if model_is_valid "$name"; then
        log "Model OK: $name"
    else
        log "Model missing or incomplete: $name"
        restore_model "$name"
    fi

    if tokenizer_is_valid "$name"; then
        log "Tokenizer OK: $name"
    else
        log "Tokenizer missing or incomplete: $name"
        restore_tokenizer "$name"
    fi
done

log "Running final validation..."

for name in "${MODEL_NAMES[@]}"; do
    if ! model_is_valid "$name"; then
        log "ERROR: model validation failed: $name"
        exit 3
    fi

    if ! tokenizer_is_valid "$name"; then
        log "ERROR: tokenizer validation failed: $name"
        exit 3
    fi
done

log "All translation assets are ready."
log "Starting Translation Service..."

exec "$@"
