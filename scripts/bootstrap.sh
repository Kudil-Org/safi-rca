#!/usr/bin/env bash
# Bootstrap safi-rca on a fresh Linux host (for example an EC2 instance).
#
# Run from anywhere inside the checkout, on a clone of the repository:
#
#     git clone https://github.com/Kudil-Org/safi-rca.git
#     cd safi-rca
#     scripts/bootstrap.sh            # core + Aider RepoMap
#     scripts/bootstrap.sh --agent    # ... plus the OpenHands model runtime
#
# What it does, and why:
#   1. The fixture mirrors under fixtures/origin/*.git are bare repositories
#      stored in-tree.  Git cannot track empty directories, so refs/heads and
#      refs/tags ship empty and git refuses to recognise the mirror as a repo on
#      a fresh clone.  Recreate them.
#   2. The submodule URL in .gitmodules is relative (./fixtures/origin/...),
#      which git resolves against the origin remote and 404s on GitHub.  Repoint
#      it at the in-tree mirror so no network fetch is needed.
#   3. Install into a virtualenv so nothing leaks into the system Python.
#
# It is idempotent: re-running it is safe.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
    cat <<'EOF'
Bootstrap safi-rca on a fresh Linux host (for example an EC2 instance).

Usage: scripts/bootstrap.sh [--agent]

  --agent   also install the OpenHands model runtime (implies the RepoMap extra)
  -h, --help   show this help

Run it from anywhere inside a clone of the repository.
EOF
}

with_agent=0
for arg in "$@"; do
    case "$arg" in
        --agent) with_agent=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "bootstrap: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

command -v git >/dev/null 2>&1 || { echo "bootstrap: git is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "bootstrap: python3 is required" >&2; exit 1; }

python3 - <<'PY' || { echo "bootstrap: need Python 3.11+" >&2; exit 1; }
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY

echo "==> restoring in-tree fixture mirrors"
for mirror in fixtures/origin/*.git; do
    mkdir -p "$mirror/refs/heads" "$mirror/refs/tags"
    [ -f "$mirror/refs/heads/.gitkeep" ] || : > "$mirror/refs/heads/.gitkeep"
    [ -f "$mirror/refs/tags/.gitkeep" ] || : > "$mirror/refs/tags/.gitkeep"
done

echo "==> wiring submodules to the in-tree mirrors"
git config submodule.fixtures/sample-repo.url "$PWD/fixtures/origin/sample-repo.git"
git config submodule.fixtures/alt-repo.url "$PWD/fixtures/origin/alt-repo.git"
git -c protocol.file.allow=always submodule update --init

echo "==> creating virtualenv"
python3 -m venv .venv 2>/dev/null || {
    echo "bootstrap: 'python3 -m venv' failed; install the venv module, e.g." >&2
    echo "           sudo apt install -y python3-venv" >&2
    exit 1
}
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install --upgrade pip >/dev/null

echo "==> installing safi-rca (core; standard library only)"
pip install -e .

extras="repomap"
if [ "$with_agent" -eq 1 ]; then
    extras="repomap,agent"
fi
echo "==> installing optional extras: $extras"
if ! pip install -e ".[$extras]"; then
    echo "bootstrap: warning: could not install [$extras]." >&2
    echo "           The analyzer still runs; RepoMap falls back to the AST map." >&2
    echo "           See README 'Environment notes' (Aider/OpenHands pin conflicts)." >&2
fi

# Keep git archive exports on the same filesystem as the checkout.  The default
# is already sane on POSIX; pinning it keeps runs reproducible and independent
# of the current working directory.
export SAFI_RCA_TMP_DIR="${SAFI_RCA_TMP_DIR:-$HOME/safi-rca-tmp}"

echo
echo "safi-rca is ready."
echo
echo "  source .venv/bin/activate"
echo "  export SAFI_RCA_TMP_DIR=$SAFI_RCA_TMP_DIR"
echo "  safi-rca runtimes"
echo "  safi-rca analyze --repo fixtures/sample-repo \\"
echo "      --sha 467b3d80a3a2c7bd0cecd81e44838bb3ff5fdc0c \\"
echo "      --evidence evidence/pytest_failure.txt"
echo
echo "For the model runtime, put a credential and LLM_MODEL in .env (see .env.example)."
