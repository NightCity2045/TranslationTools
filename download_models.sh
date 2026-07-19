#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_ROOT="${NC_TRANSLATION_MODEL_ROOT:-$ROOT_DIR/models}"
TOKENIZER_ROOT="${NC_TRANSLATION_TOKENIZER_ROOT:-$ROOT_DIR/tokenizers}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
export HF_HOME

MODEL_SPECS=(
    "opus-mt-en-ru|Helsinki-NLP/opus-mt-en-ru"
    "opus-mt-ru-en|Helsinki-NLP/opus-mt-ru-en"
)

log() {
    printf '[download-models] %s\n' "$*"
}

model_is_valid() {
    local directory="$1"

    test -d "$directory" \
        && test -s "$directory/model.bin" \
        && test -s "$directory/config.json"
}

tokenizer_is_valid() {
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

install_requirements() {
    if [[ "${NC_TRANSLATION_SKIP_PIP_INSTALL:-0}" == "1" ]]; then
        log "Python dependencies are already installed."
        return
    fi

    log "Installing Python dependencies..."

    "$PYTHON_BIN" -m pip install \
        --disable-pip-version-check \
        -r "$ROOT_DIR/requirements.txt"
}

check_torch() {
    "$PYTHON_BIN" - <<'PY'
try:
    import torch  # noqa: F401
except Exception as exc:
    raise SystemExit(
        "download_models.sh: package 'torch' is required while "
        "converting Hugging Face models to CTranslate2."
    ) from exc
PY
}

build_model() {
    local name="$1"
    local source="$2"
    local destination="$MODEL_ROOT/$name"
    local temporary="${destination}.incoming.$$"

    if model_is_valid "$destination"; then
        log "Model already valid, keeping it: $name"
        return
    fi

    if [[ -e "$destination" ]]; then
        log "Model is incomplete, rebuilding it: $name"
    else
        log "Model is missing, downloading and building it: $name"
    fi

    rm -rf "$temporary"
    mkdir -p "$temporary"

    ct2-transformers-converter \
        --force \
        --model "$source" \
        --quantization int8 \
        --output_dir "$temporary"

    if ! model_is_valid "$temporary"; then
        log "ERROR: converted model failed validation: $name"
        rm -rf "$temporary"
        exit 3
    fi

    rm -rf "$destination"
    mv "$temporary" "$destination"

    log "Model ready: $destination"
}

build_tokenizer() {
    local name="$1"
    local source="$2"
    local destination="$TOKENIZER_ROOT/$name"
    local temporary="${destination}.incoming.$$"

    if tokenizer_is_valid "$destination"; then
        log "Tokenizer already valid, keeping it: $name"
        return
    fi

    if [[ -e "$destination" ]]; then
        log "Tokenizer is incomplete, rebuilding it: $name"
    else
        log "Tokenizer is missing, downloading it: $name"
    fi

    rm -rf "$temporary"
    mkdir -p "$temporary"

    "$PYTHON_BIN" - "$source" "$temporary" <<'PY'
import sys
from pathlib import Path

from transformers import AutoTokenizer

source = sys.argv[1]
destination = Path(sys.argv[2])

destination.mkdir(parents=True, exist_ok=True)

tokenizer = AutoTokenizer.from_pretrained(source)
tokenizer.save_pretrained(destination)

print(f"Tokenizer saved: {source} -> {destination}")
PY

    if ! tokenizer_is_valid "$temporary"; then
        log "ERROR: tokenizer failed validation: $name"
        rm -rf "$temporary"
        exit 3
    fi

    rm -rf "$destination"
    mv "$temporary" "$destination"

    log "Tokenizer ready: $destination"
}

mkdir -p "$MODEL_ROOT" "$TOKENIZER_ROOT"

install_requirements
check_torch

for specification in "${MODEL_SPECS[@]}"; do
    IFS='|' read -r name source <<< "$specification"

    build_model "$name" "$source"
    build_tokenizer "$name" "$source"
done

for specification in "${MODEL_SPECS[@]}"; do
    IFS='|' read -r name source <<< "$specification"

    if ! model_is_valid "$MODEL_ROOT/$name"; then
        log "ERROR: final model validation failed: $name"
        exit 3
    fi

    if ! tokenizer_is_valid "$TOKENIZER_ROOT/$name"; then
        log "ERROR: final tokenizer validation failed: $name"
        exit 3
    fi
done

log "All translation models and tokenizers are ready."
