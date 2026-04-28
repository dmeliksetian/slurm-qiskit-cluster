#!/bin/bash
# =============================================================================
# 00-check-prereqs.sh
# Validates the host environment before building or starting the cluster.
# If podman-compose is not found on PATH or in .venv, creates .venv and
# installs it automatically. Safe to re-run.
#
# Host prerequisites (must be installed manually before running this script):
#   - git
#   - podman >= 4.0
#   - python3 + pip
#
# Usage:
#   ./setup/00-check-prereqs.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; WARN=0; FAIL=0

pass() { echo -e "  ${GREEN}✔${NC}  $*";  ((PASS++)) || true; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; ((WARN++)) || true; }
fail() { echo -e "  ${RED}✘${NC}  $*";   ((FAIL++)) || true; }
section() { echo ""; echo -e "${BOLD}${CYAN}── $* ${NC}"; }

echo ""
echo -e "${BOLD}slurm-qiskit-cluster — prerequisite check${NC}"
echo "============================================"

# ── Podman ────────────────────────────────────────────────────────────────────
section "Podman"

if command -v podman &>/dev/null; then
    PODMAN_VER=$(podman --version | awk '{print $3}')
    pass "podman found: $PODMAN_VER"

    # Minimum version 4.0 for compose support
    PODMAN_MAJOR=$(echo "$PODMAN_VER" | cut -d. -f1)
    if [[ "$PODMAN_MAJOR" -ge 4 ]]; then
        pass "podman version >= 4.0 (compose support OK)"
    else
        warn "podman version < 4.0 — upgrade recommended for compose support"
    fi
else
    fail "podman not found"
    echo ""
    echo "    Install podman:"
    echo "      WSL2 / Fedora:  sudo dnf install podman"
    echo "      Ubuntu:         sudo apt install podman"
    echo "      RHEL:           sudo subscription-manager repos --enable ...; sudo dnf install podman"
    echo "      Official docs:  https://podman.io/docs/installation"
fi


# ── Git ───────────────────────────────────────────────────────────────────────
section "Git and submodules"

if command -v git &>/dev/null; then
    GIT_VER=$(git --version | awk '{print $3}')
    pass "git found: $GIT_VER"
else
    fail "git not found — install with: sudo dnf install git  OR  sudo apt install git"
fi

# Check submodules are initialised
QRMI_DIR="$REPO_ROOT/shared/qrmi"
SPANK_DIR="$REPO_ROOT/shared/spank-plugins"

if [[ -f "$QRMI_DIR/Cargo.toml" ]]; then
    QRMI_COMMIT=$(git -C "$REPO_ROOT" submodule status shared/qrmi 2>/dev/null | awk '{print substr($1,1,8)}')
    pass "shared/qrmi submodule initialised (commit: $QRMI_COMMIT)"
else
    fail "shared/qrmi submodule not initialised"
    echo "    Run: git submodule update --init --recursive"
fi

if [[ -d "$SPANK_DIR/plugins" ]]; then
    SPANK_COMMIT=$(git -C "$REPO_ROOT" submodule status shared/spank-plugins 2>/dev/null | awk '{print substr($1,1,8)}')
    pass "shared/spank-plugins submodule initialised (commit: $SPANK_COMMIT)"
else
    fail "shared/spank-plugins submodule not initialised"
    echo "    Run: git submodule update --init --recursive"
fi

# ── Python and host environment ───────────────────────────────────────────────
section "Python and host environment"

PYTHON3=""
if command -v python3 &>/dev/null; then
    PYTHON3="python3"
    pass "python3 found: $(python3 --version)"
else
    fail "python3 not found — install with: sudo apt install python3  OR  sudo dnf install python3"
    echo "    python3 is required to create the .venv for podman-compose."
fi

if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
    pass "pip found"
else
    fail "pip not found — install with: sudo apt install python3-pip  OR  sudo dnf install python3-pip"
fi

# podman-compose: check system PATH, then .venv/bin, then auto-create .venv
VENV_DIR="$REPO_ROOT/.venv"
if command -v podman-compose &>/dev/null; then
    PC_VER=$(podman-compose --version 2>/dev/null | head -1 || true)
    pass "podman-compose found (system): $PC_VER"
elif [[ -x "$VENV_DIR/bin/podman-compose" ]]; then
    PC_VER=$("$VENV_DIR/bin/podman-compose" --version 2>/dev/null | head -1 || true)
    pass "podman-compose found in .venv: $PC_VER"
elif [[ -n "$PYTHON3" ]]; then
    echo -e "  ${CYAN}→${NC}  podman-compose not found — creating .venv and installing ..."
    "$PYTHON3" -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --quiet podman-compose
    PC_VER=$("$VENV_DIR/bin/podman-compose" --version 2>/dev/null | head -1 || true)
    pass "podman-compose installed in .venv: $PC_VER"
    echo "      Subsequent setup scripts add .venv/bin to PATH automatically."
else
    fail "podman-compose not found and python3 unavailable — cannot auto-install"
    echo "    Install manually: pip install podman-compose  OR  dnf install podman-compose"
fi

# ── Credentials ───────────────────────────────────────────────────────────────
section "Credentials"

QRMI_CONFIG="$REPO_ROOT/cluster/config/qrmi_config.json"
QRMI_EXAMPLE="$REPO_ROOT/cluster/config/qrmi_config.json.example"

if [[ -f "$QRMI_CONFIG" ]]; then
    if grep -q "<YOUR" "$QRMI_CONFIG" 2>/dev/null; then
        warn "qrmi_config.json exists but still contains unfilled placeholders"
        echo "    Run: ./setup/03-configure-credentials.sh"
    else
        pass "qrmi_config.json found and appears complete"
    fi
else
    warn "qrmi_config.json not found"
    echo "    Run: ./setup/03-configure-credentials.sh"
fi

# ── GPU (optional) ────────────────────────────────────────────────────────────
section "GPU (optional — required for g1 and qg1 nodes)"

HAS_GPU=0
if [[ -e /dev/dxg ]] || (command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1); then
    HAS_GPU=1
fi

if [[ "$HAS_GPU" -eq 1 ]]; then
    if [[ -e /dev/dxg ]]; then
        pass "/dev/dxg found — WSL2 NVIDIA GPU passthrough available"
    fi
    GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)
    [[ -n "$GPU" ]] && pass "GPU: $GPU"

    # CUDA version
    CUDA_FULL=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[\d.]+' | head -1 || true)
    CUDA_MAJOR=$(echo "${CUDA_FULL:-0}" | cut -d. -f1)
    if [[ -n "$CUDA_FULL" ]]; then
        if [[ "$CUDA_MAJOR" -ge 11 && "$CUDA_MAJOR" -le 13 ]]; then
            pass "CUDA version: $CUDA_FULL (supported)"
        elif [[ "$CUDA_MAJOR" -gt 13 ]]; then
            warn "CUDA version: $CUDA_FULL — newer than tested range (11–13), may work but untested"
        else
            warn "CUDA version: $CUDA_FULL — older than supported range (11–13)"
        fi
    fi

    # Compute capability
    COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)
    [[ -n "$COMPUTE_CAP" ]] && pass "Compute capability: $COMPUTE_CAP"
else
    warn "No GPU detected — g1 and qg1 nodes will not function"
    echo "    GPU is optional. c1, c2, q1 work without it."
    echo "    WSL2 GPU setup: docs/wsl2-nvidia.md"
fi

# ── Disk space ────────────────────────────────────────────────────────────────
section "Disk space"

AVAILABLE=$(df -BG "$REPO_ROOT" | awk 'NR==2 {gsub("G",""); print $4}')
if [[ "$AVAILABLE" -ge 20 ]]; then
    pass "${AVAILABLE}GB available at $REPO_ROOT (20GB minimum recommended)"
elif [[ "$AVAILABLE" -ge 10 ]]; then
    warn "${AVAILABLE}GB available — 20GB recommended (images + pyenv are large)"
else
    fail "${AVAILABLE}GB available — likely insufficient (20GB recommended)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
echo -e "  ${GREEN}Passed${NC}: $PASS   ${YELLOW}Warnings${NC}: $WARN   ${RED}Failed${NC}: $FAIL"
echo "════════════════════════════════════════════"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}Fix the failed checks above before continuing.${NC}"
    exit 1
elif [[ "$WARN" -gt 0 ]]; then
    echo -e "${YELLOW}Warnings present — review before continuing.${NC}"
    echo -e "Next step: ${CYAN}./setup/01-build-images.sh${NC}"
else
    echo -e "${GREEN}All checks passed.${NC}"
    echo -e "Next step: ${CYAN}./setup/01-build-images.sh${NC}"
fi
echo ""
