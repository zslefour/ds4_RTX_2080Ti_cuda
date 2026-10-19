#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Auto-detect CUDA from nvcc if CUDA_HOME is not already set.
if [ -z "${CUDA_HOME:-}" ] && command -v nvcc >/dev/null 2>&1; then
    CUDA_HOME="$(dirname "$(dirname "$(command -v nvcc)")")"
fi
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# RTX 2080 Ti 22 GiB Turing profile.
# This card has the same sm_75 compute capability as the 11 GiB variant but
# twice the VRAM, so we can keep a larger persistent expert cache and a
# longer context while still leaving headroom for the prefill workspace and
# the model weights that live on the GPU.
export DS4_CUDA_MMQ="${DS4_CUDA_MMQ:-0}"
export DS4_CUDA_NO_Q8_F16_CACHE=1
export DS4_CUDA_WEIGHT_ARENA_CHUNK_MB="${DS4_CUDA_WEIGHT_ARENA_CHUNK_MB:-256}"
export DS4_CUDA_LAZY_KV_CACHE="${DS4_CUDA_LAZY_KV_CACHE:-1}"
export DS4_CUDA_LAZY_KV_INITIAL_TOKENS="${DS4_CUDA_LAZY_KV_INITIAL_TOKENS:-4096}"

export DS4_CUDA_STREAMING_READ_THREADS="${DS4_CUDA_STREAMING_READ_THREADS:-4}"
export DS4_CUDA_STREAMING_SMALL_MISS_PARALLEL="${DS4_CUDA_STREAMING_SMALL_MISS_PARALLEL:-1}"
export DS4_CUDA_STREAMING_PERSISTENT_READERS="${DS4_CUDA_STREAMING_PERSISTENT_READERS:-1}"
export DS4_CUDA_STREAMING_NUMA_AFFINITY="${DS4_CUDA_STREAMING_NUMA_AFFINITY:-1}"
export DS4_CUDA_DECODE_CACHE_LRU="${DS4_CUDA_DECODE_CACHE_LRU:-1}"
export DS4_CUDA_DYNAMIC_TIER_PROMOTION="${DS4_CUDA_DYNAMIC_TIER_PROMOTION:-1}"
export DS4_CUDA_EXPERT_MAP="${DS4_CUDA_EXPERT_MAP:-1}"

exec ./ds4-server \
    --cuda \
    -m "$script_dir/ds4flash.gguf" \
    --ssd-streaming \
    --ssd-streaming-cache-experts "${DS4_SERVER_EXPERT_CACHE:-10GB}" \
    --prefill-chunk "${DS4_SERVER_PREFILL_CHUNK:-1024}" \
    --ctx "${DS4_SERVER_CTX:-65536}" \
    --kv-disk-dir "${DS4_SERVER_KV_DIR:-$script_dir/.cache/server-kv}" \
    --kv-disk-space-mb "${DS4_SERVER_KV_CACHE_MB:-4096}" \
    --kv-cache-min-tokens "${DS4_SERVER_KV_MIN_TOKENS:-16}" \
    --host "${DS4_SERVER_HOST:-127.0.0.1}" \
    --port "${DS4_SERVER_PORT:-18099}" \
    --cors \
    "$@"
