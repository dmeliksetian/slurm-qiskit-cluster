#!/bin/bash
# =============================================================================
# 05-verify.sh
# End-to-end smoke tests for the running slurm-qiskit-cluster.
# Tests each layer in order: Slurm → MPI → Python/Qiskit → QRMI → GPU.
# Safe to run multiple times — submits test jobs but cleans up after itself.
#
# Usage:
#   ./setup/05-verify.sh [--gpu] [--qrmi]
#
# Options:
#   --gpu     Include GPU tests (requires g1 node with NVIDIA GPU)
#   --qrmi    Include QRMI connectivity test (requires valid credentials
#             and network access to IBM Quantum / Pasqal)
#
# Without options, only local tests are run (no credentials or GPU needed).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; WARN=0; FAIL=0

pass() { echo -e "  ${GREEN}✔${NC}  $*"; ((PASS++)) || true; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; ((WARN++)) || true; }
fail() { echo -e "  ${RED}✘${NC}  $*"; ((FAIL++)) || true; }
section() { echo ""; echo -e "${BOLD}${CYAN}── $* ${NC}"; }
info() { echo -e "    ${CYAN}→${NC} $*"; }

# ── Parse arguments ───────────────────────────────────────────────────────────
TEST_GPU=0
TEST_QRMI=0
for arg in "$@"; do
    case $arg in
        --gpu)  TEST_GPU=1  ;;
        --qrmi) TEST_QRMI=1 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

echo ""
echo -e "${BOLD}slurm-qiskit-cluster — verification${NC}"
echo "======================================"
[[ "$TEST_GPU"  -eq 1 ]] && echo "  GPU tests:  enabled"  || echo "  GPU tests:  disabled (--gpu to enable)"
[[ "$TEST_QRMI" -eq 1 ]] && echo "  QRMI tests: enabled"  || echo "  QRMI tests: disabled (--qrmi to enable)"

# ── Helper: run command in container ─────────────────────────────────────────
run_in() {
    local container=$1; shift
    podman exec "$container" bash -lc "$*" 2>&1
}

# ── Helper: submit a batch job and wait for result ────────────────────────────
submit_and_wait() {
    local container=$1
    local script=$2
    local job_name=$3
    local timeout=${4:-30}

    # Submit
    local job_id
    job_id=$(podman exec "$container" bash -lc "echo '$script' | sbatch --job-name=$job_name --wrap='$script' --output=/tmp/${job_name}-%j.out" 2>&1 | grep -oP '(?<=Submitted batch job )\d+')

    if [[ -z "$job_id" ]]; then
        echo "SUBMIT_FAILED"
        return
    fi

    # Wait for completion
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local state
        state=$(podman exec "$container" bash -lc "squeue -j $job_id -h -o %T 2>/dev/null || echo DONE")
        if [[ "$state" == "DONE" ]] || [[ -z "$state" ]]; then
            break
        fi
        sleep 2
        ((elapsed+=2)) || true
    done

    # Return output
    podman exec "$container" bash -lc "cat /tmp/${job_name}-${job_id}.out 2>/dev/null || echo NO_OUTPUT"
}

# =============================================================================
# TEST 1 — Containers running
# =============================================================================
section "Containers"

for node in slurmctld slurmdbd mysql c1 c2 q1; do
    if podman ps --format "{{.Names}}" | grep -q "^${node}$"; then
        pass "$node is running"
    else
        fail "$node is not running — run: ./setup/04-start-cluster.sh"
    fi
done

if [[ "$TEST_GPU" -eq 1 ]]; then
    if podman ps --format "{{.Names}}" | grep -q "^g1$"; then
        pass "g1 is running"
    else
        fail "g1 is not running"
    fi
fi

# =============================================================================
# TEST 2 — Slurm
# =============================================================================
section "Slurm"

if run_in slurmctld sinfo &>/dev/null; then
    SINFO=$(run_in slurmctld sinfo 2>&1)
    pass "sinfo responds"
    info "$SINFO"
else
    fail "sinfo failed — slurmctld may not be ready"
fi

if run_in slurmctld squeue &>/dev/null; then
    pass "squeue responds"
else
    fail "squeue failed"
fi

# Check SPANK plugin
if run_in slurmctld "sbatch --help 2>&1 | grep -q 'qpu'"; then
    pass "SPANK plugin loaded (--qpu option visible in sbatch --help)"
else
    fail "SPANK plugin not loaded — check plugstack.conf and spank_qrmi.so"
    info "Expected: optional /shared/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so"
fi

# =============================================================================
# TEST 3 — /shared/pyenv
# =============================================================================
section "Shared Python environment"

for node in c1 c2 q1; do
    if run_in $node "test -f /shared/pyenv/bin/activate" &>/dev/null; then
        pass "$node: /shared/pyenv is mounted"
    else
        fail "$node: /shared/pyenv not found — check volume mount in docker-compose.yml"
        continue
    fi

    if run_in $node "python3 -c 'import qiskit; print(qiskit.__version__)'" &>/dev/null; then
        VER=$(run_in $node "python3 -c 'import qiskit; print(qiskit.__version__)'" 2>&1)
        pass "$node: qiskit $VER importable"
    else
        fail "$node: qiskit import failed"
    fi

    if run_in $node "python3 -c 'import qrmi; print(\"ok\")'" &>/dev/null; then
        pass "$node: qrmi importable"
    else
        fail "$node: qrmi import failed — check qrmi wheel in /shared/pyenv"
    fi
done

# =============================================================================
# TEST 4 — MPI
# =============================================================================
section "MPI (mpi4py)"

MPI_OUTPUT=$(run_in c1 "python3 -c 'from mpi4py import MPI; print(MPI.COMM_WORLD.Get_rank())'" 2>&1)
if echo "$MPI_OUTPUT" | grep -q "^0"; then
    pass "mpi4py works on c1"
else
    fail "mpi4py test failed on c1: $MPI_OUTPUT"
fi

# =============================================================================
# TEST 5 — Qiskit circuit (local simulation)
# =============================================================================
section "Qiskit local simulation"

QISKIT_TEST='
from qiskit import QuantumCircuit
from qiskit.primitives import StatevectorSampler
qc = QuantumCircuit(2, 2)
qc.h(0)
qc.cx(0, 1)
qc.measure([0,1], [0,1])
sampler = StatevectorSampler()
job = sampler.run([qc], shots=100)
result = job.result()
counts = result[0].data.meas.get_counts()
print("counts:", counts)
assert set(counts.keys()).issubset({"00", "11"}), f"Unexpected counts: {counts}"
print("PASS")
'

QISKIT_OUTPUT=$(run_in c1 "python3 -c '$QISKIT_TEST'" 2>&1)
if echo "$QISKIT_OUTPUT" | grep -q "PASS"; then
    pass "Bell state circuit executed correctly on c1"
    info "$(echo "$QISKIT_OUTPUT" | grep counts)"
else
    fail "Qiskit local simulation failed"
    info "$QISKIT_OUTPUT"
fi

# =============================================================================
# TEST 6 — Slurm batch job (c1)
# =============================================================================
section "Slurm batch job"

BATCH_SCRIPT="python3 -c 'import qiskit; print(qiskit.__version__)'"
JOB_OUTPUT=$(submit_and_wait "slurmctld" "$BATCH_SCRIPT" "verify-qiskit" 30)

if echo "$JOB_OUTPUT" | grep -qP '^\d+\.\d+'; then
    pass "Batch job completed — qiskit $(echo $JOB_OUTPUT | tr -d '\n')"
else
    fail "Batch job did not produce expected output"
    info "$JOB_OUTPUT"
fi

# =============================================================================
# TEST 7 — GPU (optional)
# =============================================================================
if [[ "$TEST_GPU" -eq 1 ]]; then
    section "GPU (g1)"

    if run_in g1 "python3 -c 'import cupy; print(cupy.__version__)'" &>/dev/null; then
        VER=$(run_in g1 "python3 -c 'import cupy; print(cupy.__version__)'" 2>&1)
        pass "cupy $VER importable on g1"
    else
        fail "cupy import failed on g1 — check CUDA libs and /usr/lib/wsl/lib mount"
    fi

    if run_in g1 "python3 -c 'import cupy; a = cupy.array([1,2,3]); print(a.sum())'" &>/dev/null; then
        pass "cupy GPU array operation succeeded on g1"
    else
        fail "cupy GPU operation failed on g1"
    fi
fi

# =============================================================================
# TEST 8 — QRMI connectivity (optional)
# =============================================================================
if [[ "$TEST_QRMI" -eq 1 ]]; then
    section "QRMI connectivity"

    QRMI_TEST='
from qrmi.primitives import QRMIService
service = QRMIService()
resources = service.resources()
print(f"Backends found: {len(resources)}")
for r in resources:
    print(f"  - {r.name} ({r.backend_type})")
print("PASS")
'
    QRMI_OUTPUT=$(run_in q1 "python3 -c '$QRMI_TEST'" 2>&1)
    if echo "$QRMI_OUTPUT" | grep -q "PASS"; then
        pass "QRMI service initialised successfully"
        echo "$QRMI_OUTPUT" | grep -E "(Backends|  -)" | while read -r line; do
            info "$line"
        done
    else
        fail "QRMI service initialisation failed"
        info "$QRMI_OUTPUT"
        info "Check credentials in /etc/slurm/qrmi_config.json"
        info "Check plugstack.conf on q1"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "════════════════════════════════════════════"
echo -e "  ${GREEN}Passed${NC}: $PASS   ${YELLOW}Warnings${NC}: $WARN   ${RED}Failed${NC}: $FAIL"
echo "════════════════════════════════════════════"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}Some tests failed — review output above.${NC}"
    echo ""
    echo "  Useful commands:"
    echo "    podman compose logs -f"
    echo "    podman exec -it c1 bash"
    echo "    podman exec -it q1 bash"
    exit 1
else
    echo -e "${GREEN}All tests passed.${NC}"
    echo ""
    echo "  Your cluster is ready. Try running a job:"
    echo "    podman exec -it c1 bash"
    echo "    sbatch --wrap='python3 /path/to/your/job.py'"
    echo ""
fi
