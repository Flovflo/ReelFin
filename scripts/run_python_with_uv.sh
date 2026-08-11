#!/usr/bin/env bash
# The QA suite intentionally never falls back to the host Python.
set -euo pipefail

readonly REELFIN_MANAGED_UV="/Users/flo/.local/share/reelfin-codex/uv/bin/uv"
readonly REELFIN_MANAGED_PYTHON_ROOT="/Users/flo/.local/share/reelfin-codex/uv/python"
readonly REELFIN_MANAGED_UV_CACHE="/Users/flo/.cache/reelfin-codex/uv"
readonly REELFIN_MANAGED_PYTHON_REQUEST="3.13"

export UV_PYTHON_INSTALL_DIR="${REELFIN_MANAGED_PYTHON_ROOT}"
export UV_CACHE_DIR="${REELFIN_MANAGED_UV_CACHE}"
export PYTHONDONTWRITEBYTECODE=1

if [[ ! -x "${REELFIN_MANAGED_UV}" ]]; then
  echo "Managed ReelFin uv is unavailable; refusing to run Python." >&2
  exit 69
fi

managed_python="$(
  "${REELFIN_MANAGED_UV}" python find \
    --offline \
    --no-project \
    --no-config \
    --no-python-downloads \
    --managed-python \
    "${REELFIN_MANAGED_PYTHON_REQUEST}" 2>/dev/null
)" || {
  echo "Managed Python 3.13 is unavailable; refusing to run Python." >&2
  exit 69
}

canonical_root="$(cd "${REELFIN_MANAGED_PYTHON_ROOT}" && pwd -P)" || exit 69
canonical_python="$(cd "$(dirname "${managed_python}")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "${managed_python}")")" || exit 69
if [[ ! -x "${canonical_python}" || "${canonical_python}" != "${canonical_root}/"* ]]; then
  echo "Managed Python resolved outside the ReelFin runtime; refusing to run." >&2
  exit 69
fi

python_identity="$(
  "${REELFIN_MANAGED_UV}" run \
    --quiet \
    --offline \
    --no-project \
    --no-config \
    --no-env-file \
    --no-python-downloads \
    --managed-python \
    --python "${canonical_python}" \
    python -c 'import pathlib, sys; print(f"{sys.version_info.major}.{sys.version_info.minor}|{pathlib.Path(sys.executable).resolve()}")'
)" || exit 69
if [[ "${python_identity}" != "3.13|${canonical_python}" ]]; then
  echo "Managed Python identity verification failed; refusing to run." >&2
  exit 69
fi

exec "${REELFIN_MANAGED_UV}" run \
  --quiet \
  --offline \
  --no-project \
  --no-config \
  --no-env-file \
  --no-python-downloads \
  --managed-python \
  --python "${canonical_python}" \
  python "$@"
