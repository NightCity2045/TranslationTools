#!/usr/bin/env bash
set -Eeuo pipefail

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

model_directory_is_valid() {
    local directory="$1"

    test -d "$directory" \
        && test -s "$directory/model.bin" \
        && test -s "$directory/config.json"
}

tokenizer_directory_is_valid() {
    local directory="$1"

    test -d "$directory" \
        && test -s "$directory/tokenizer_config.json" \
        && {
            test -s "$directory/tokenizer.json" \
                || {
                    test -s "$directory/source.spm" \
                        && test -s "$directory/target.spm" \
                        && test -s "$directory/vocab.json"
                }
        }
}

restore_directory() {
    local asset_type="$1"
    local name="$2"
    local source="$3"
    local destination="$4"
    local validator="$5"

    local temporary="${destination}.incoming.$$"

    if ! "$validator" "$source"; then
        log "ERROR: bundled $asset_type is missing or damaged: $source"
        exit 3
    fi

    log "Restoring $asset_type: $name"

    rm -rf "$temporary"
    mkdir -p "$temporary"

    cp -a "$source/." "$temporary/"

    if ! "$validator" "$temporary"; then
        log "ERROR: copied $asset_type failed validation: $name"
        rm -rf "$temporary"
        exit 3
    fi

    rm -rf "$destination"
    mv "$temporary" "$destination"

    log "Restored $asset_type: $name"
}

ensure_model() {
    local name="$1"

    local source="$SEED_MODEL_ROOT/$name"
    local destination="$MODEL_ROOT/$name"

    if model_directory_is_valid "$destination"; then
        log "Model OK: $name"
        return
    fi

    if [[ -e "$destination" ]]; then
        log "Model is incomplete or damaged: $name"
    else
        log "Model is missing: $name"
    fi

    restore_directory \
        "model" \
        "$name" \
        "$source" \
        "$destination" \
        model_directory_is_valid
}

ensure_tokenizer() {
    local name="$1"

    local source="$SEED_TOKENIZER_ROOT/$name"
    local destination="$TOKENIZER_ROOT/$name"

    if tokenizer_directory_is_valid "$destination"; then
        log "Tokenizer OK: $name"
        return
    fi

    if [[ -e "$destination" ]]; then
        log "Tokenizer is incomplete or damaged: $name"
    else
        log "Tokenizer is missing: $name"
    fi

    restore_directory \
        "tokenizer" \
        "$name" \
        "$source" \
        "$destination" \
        tokenizer_directory_is_valid
}

log "Checking translation assets..."
log "Model root: $MODEL_ROOT"
log "Tokenizer root: $TOKENIZER_ROOT"

mkdir -p "$MODEL_ROOT"
mkdir -p "$TOKENIZER_ROOT"

for name in "${MODEL_NAMES[@]}"; do
    ensure_model "$name"
    ensure_tokenizer "$name"
done

log "Running final validation..."

for name in "${MODEL_NAMES[@]}"; do
    if ! model_directory_is_valid "$MODEL_ROOT/$name"; then
        log "ERROR: final model validation failed: $name"
        exit 3
    fi

    if ! tokenizer_directory_is_valid "$TOKENIZER_ROOT/$name"; then
        log "ERROR: final tokenizer validation failed: $name"
        exit 3
    fi
done

log "All translation assets are ready."
log "Starting requested command..."

exec "$@"
