#!/bin/bash
# =============================================================================
# 00b-configure-system.sh
# Detects host hardware and renders system-specific config files from templates.
# Run once after 00-check-prereqs.sh, before 01-build-images.sh.
#
# Templates (tracked in git, contain @@PLACEHOLDER@@ tokens):
#   cluster/config/slurm.conf.template
#   cluster/config/gres.conf.template
#   cluster/docker-compose.yml.template
#
# Generated files (gitignored, overwritten each run):
#   cluster/config/slurm.conf
#   cluster/config/gres.conf
#   cluster/docker-compose.yml
#   .env  (CUDA_VERSION and SLURM_CPUS_PER_NODE updated in-place)
#
# Placeholders filled:
#   @@CPU_COUNT@@        total logical CPUs
#   @@SOCKETS@@          sockets per board
#   @@CORES_PER_SOCKET@@ physical cores per socket
#   @@THREADS_PER_CORE@@ hardware threads per core
#   @@MEM_MB@@           usable RAM in MB (95% of total)
#   @@GPU_TYPE@@         GPU model slug e.g. rtx2080ti
#   @@GPU_DEVICE@@       device path: /dev/dxg (WSL2) or /dev/nvidia0 (bare metal)
#   @@WSL2_LIB_MOUNT@@  WSL2: the /usr/lib/wsl/lib volume line; bare metal: line omitted
#
# Usage:
#   ./setup/00b-configure-system.sh [--dry-run] [--no-gpu]
#
#   --dry-run   Show detected values without writing any files
#   --no-gpu    Skip GPU detection; GPU placeholders set to disabled values
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_DIR="$REPO_ROOT/cluster"
CONFIG_DIR="$CLUSTER_DIR/config"
ENV_FILE="$REPO_ROOT/.env"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[sysconf]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}    $*"; }
die()     { echo -e "${RED}[error]${NC}   $*" >&2; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────
DRY_RUN=0
NO_GPU=0
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=1 ;;
        --no-gpu)  NO_GPU=1  ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

echo ""
echo -e "${BOLD}slurm-qiskit-cluster — system configuration${NC}"
echo "============================================"
[[ "$DRY_RUN" -eq 1 ]] && warn "DRY RUN — no files will be written"
echo ""

# ── Verify templates exist ────────────────────────────────────────────────────
for tmpl in \
    "$CONFIG_DIR/slurm.conf.template" \
    "$CONFIG_DIR/gres.conf.template" \
    "$CLUSTER_DIR/docker-compose.yml.template"
do
    [[ -f "$tmpl" ]] || die "Template not found: $tmpl"
done

# ── Load .env if present ──────────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

# =============================================================================
# 1. CPU TOPOLOGY
# =============================================================================
echo -e "${BOLD}${CYAN}── CPU topology${NC}"

CPU_COUNT=$(lscpu | awk '/^CPU\(s\):/{print $NF}' | head -1)
SOCKETS=$(lscpu | awk '/^Socket\(s\):/{print $NF}')
CORES_PER_SOCKET=$(lscpu | awk '/^Core\(s\) per socket:/{print $NF}')
THREADS_PER_CORE=$(lscpu | awk '/^Thread\(s\) per core:/{print $NF}')

info "Total logical CPUs:    $CPU_COUNT"
info "Sockets:               $SOCKETS"
info "Cores per socket:      $CORES_PER_SOCKET"
info "Threads per core:      $THREADS_PER_CORE"

# =============================================================================
# 2. RAM
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}── Memory${NC}"

TOTAL_MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
MEM_MB=$(( TOTAL_MEM_MB * 95 / 100 ))

info "Total host RAM:        ${TOTAL_MEM_MB} MB"
info "Slurm RealMemory:      ${MEM_MB} MB  (95% of total)"

# =============================================================================
# 3. GPU
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}── GPU${NC}"

HAS_GPU=0
IS_WSL2=0
GPU_DEVICE=""
GPU_TYPE=""
CUDA_VER=""
WSL2_LIB_MOUNT=""

if [[ "$NO_GPU" -eq 1 ]]; then
    warn "--no-gpu specified — skipping GPU detection"
    GPU_DEVICE="/dev/null"
    GPU_TYPE="none"
else
    # WSL2 check
    if [[ -e /dev/dxg ]]; then
        IS_WSL2=1
        HAS_GPU=1
        GPU_DEVICE="/dev/dxg"
        WSL2_LIB_MOUNT="      - /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro"
        info "WSL2 detected (/dev/dxg present)"
    fi

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
        HAS_GPU=1

        GPU_FULL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)

        # Slug: strip common vendor/product prefixes, lowercase, remove spaces+dashes
        GPU_TYPE=$(echo "$GPU_FULL" \
            | sed 's/NVIDIA //I; s/GeForce //I; s/Quadro //I; s/Tesla //I' \
            | sed 's/RTX /rtx/I; s/GTX /gtx/I' \
            | tr '[:upper:]' '[:lower:]' \
            | tr -d ' -')

        # CUDA: "12.9" → "12-9"
        CUDA_FULL=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[\d.]+' | head -1 || true)
        [[ -n "$CUDA_FULL" ]] && CUDA_VER=$(echo "$CUDA_FULL" | tr '.' '-')

        # Bare metal device node
        if [[ "$IS_WSL2" -eq 0 ]]; then
            GPU_DEVICE=$(ls /dev/nvidia0 2>/dev/null \
                      || ls /dev/dri/renderD128 2>/dev/null \
                      || echo "/dev/nvidia0")
        fi

        info "GPU:                   $GPU_FULL"
        info "GPU slug (gres type):  $GPU_TYPE"
        info "GPU device:            $GPU_DEVICE"
        [[ -n "$CUDA_VER" ]] && info "CUDA version:          $CUDA_FULL  (package suffix: $CUDA_VER)"
    fi

    if [[ "$HAS_GPU" -eq 0 ]]; then
        warn "No GPU detected — g1 and qg1 nodes will not function"
        GPU_DEVICE="/dev/null"
        GPU_TYPE="none"
    fi
fi

# =============================================================================
# 4. SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Resolved values${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo "  @@CPU_COUNT@@        = $CPU_COUNT"
echo "  @@SOCKETS@@          = $SOCKETS"
echo "  @@CORES_PER_SOCKET@@ = $CORES_PER_SOCKET"
echo "  @@THREADS_PER_CORE@@ = $THREADS_PER_CORE"
echo "  @@MEM_MB@@           = $MEM_MB"
echo "  @@GPU_TYPE@@         = $GPU_TYPE"
echo "  @@GPU_DEVICE@@       = $GPU_DEVICE"
if [[ -n "$WSL2_LIB_MOUNT" ]]; then
    echo "  @@WSL2_LIB_MOUNT@@  = $WSL2_LIB_MOUNT"
else
    echo "  @@WSL2_LIB_MOUNT@@  = (line omitted — bare metal)"
fi
[[ -n "$CUDA_VER" ]] && echo "  CUDA_VERSION (.env)  = $CUDA_VER"
echo "  SLURM_CPUS_PER_NODE  = $CPU_COUNT"
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "Dry run complete — no files written."
    echo ""
    echo "Files that would be generated:"
    echo "  $CONFIG_DIR/slurm.conf"
    echo "  $CONFIG_DIR/gres.conf"
    echo "  $CLUSTER_DIR/docker-compose.yml"
    [[ -f "$ENV_FILE" ]] && echo "  $ENV_FILE  (CUDA_VERSION, SLURM_CPUS_PER_NODE updated)"
    exit 0
fi

read -rp "Generate config files with these values? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted — no files written."; exit 0; }
echo ""

# =============================================================================
# 5. RENDER HELPER
# =============================================================================
# Uses Python for substitution to safely handle values that contain slashes,
# special characters, or (for WSL2_LIB_MOUNT) embedded newlines.
render_template() {
    local src="$1" dst="$2"
    python3 - "$src" "$dst" \
        "$CPU_COUNT" "$SOCKETS" "$CORES_PER_SOCKET" "$THREADS_PER_CORE" \
        "$MEM_MB" "$GPU_TYPE" "$GPU_DEVICE" "$WSL2_LIB_MOUNT" \
<<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
(cpu_count, sockets, cores_per_socket, threads_per_core,
 mem_mb, gpu_type, gpu_device, wsl2_lib_mount) = sys.argv[3:]

with open(src) as f:
    content = f.read()

content = content.replace('@@CPU_COUNT@@',        cpu_count)
content = content.replace('@@SOCKETS@@',          sockets)
content = content.replace('@@CORES_PER_SOCKET@@', cores_per_socket)
content = content.replace('@@THREADS_PER_CORE@@', threads_per_core)
content = content.replace('@@MEM_MB@@',           mem_mb)
content = content.replace('@@GPU_TYPE@@',         gpu_type)
content = content.replace('@@GPU_DEVICE@@',       gpu_device)

# @@WSL2_LIB_MOUNT@@ — either replace with the volume line, or remove the
# entire line so we don't leave a blank line in the YAML.
if wsl2_lib_mount:
    content = content.replace('@@WSL2_LIB_MOUNT@@', wsl2_lib_mount)
else:
    lines = [l for l in content.split('\n') if '@@WSL2_LIB_MOUNT@@' not in l]
    content = '\n'.join(lines)

with open(dst, 'w') as f:
    f.write(content)
PYEOF
}

# =============================================================================
# 6. RENDER TEMPLATES
# =============================================================================
info "Rendering cluster/config/slurm.conf ..."
render_template \
    "$CONFIG_DIR/slurm.conf.template" \
    "$CONFIG_DIR/slurm.conf"
success "slurm.conf written"

info "Rendering cluster/config/gres.conf ..."
render_template \
    "$CONFIG_DIR/gres.conf.template" \
    "$CONFIG_DIR/gres.conf"
success "gres.conf written"

info "Rendering cluster/docker-compose.yml ..."
render_template \
    "$CLUSTER_DIR/docker-compose.yml.template" \
    "$CLUSTER_DIR/docker-compose.yml"
success "docker-compose.yml written"

# =============================================================================
# 7. UPDATE .env
# =============================================================================
if [[ -f "$ENV_FILE" ]]; then
    info "Updating .env ..."

    upsert_env() {
        local key="$1" val="$2"
        if grep -q "^${key}=" "$ENV_FILE"; then
            sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
        else
            echo "${key}=${val}" >> "$ENV_FILE"
        fi
    }

    upsert_env "SLURM_CPUS_PER_NODE" "$CPU_COUNT"
    [[ -n "$CUDA_VER" ]] && upsert_env "CUDA_VERSION" "$CUDA_VER"

    success ".env updated"
else
    warn ".env not found — skipping (run: cp .env.example .env)"
fi

# =============================================================================
# 8. VERIFY — no placeholders should remain
# =============================================================================
echo ""
info "Verifying generated files ..."
LEFTOVER=0
for f in \
    "$CONFIG_DIR/slurm.conf" \
    "$CONFIG_DIR/gres.conf" \
    "$CLUSTER_DIR/docker-compose.yml"
do
    if grep -q '@@' "$f" 2>/dev/null; then
        warn "Unfilled placeholders remain in: $f"
        grep -n '@@' "$f"
        ((LEFTOVER++)) || true
    fi
done
[[ "$LEFTOVER" -eq 0 ]] && success "All placeholders resolved"

# =============================================================================
# 9. SHOW RESULTS
# =============================================================================
echo ""
echo -e "${BOLD}Generated slurm.conf node lines:${NC}"
grep "^NodeName=" "$CONFIG_DIR/slurm.conf"
echo ""
echo -e "${BOLD}Generated gres.conf:${NC}"
cat "$CONFIG_DIR/gres.conf"
echo ""

echo -e "${GREEN}System configuration complete.${NC}"
echo ""
echo -e "Next step: ${CYAN}./setup/01-build-images.sh${NC}"
echo ""
