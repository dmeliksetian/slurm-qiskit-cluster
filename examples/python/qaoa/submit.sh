#!/bin/bash
# submit.sh — Initialise QAOA state and launch the quantum-classical loop.
#
# The loop runs autonomously:
#   quantum_step → classical_step → quantum_step → ... → classical_step (converged)
#
# Each quantum_step chains to the next classical_step via --dependency=afterok.
# Each classical_step re-submits the next quantum_step if not yet converged.

set -euo pipefail
cd "$(dirname "$0")"

# ── Submit first quantum step to get its job ID ───────────────────────────
JOB_ID=$(sbatch --parsable \
    --output="logs/%j/%j-quantum.out" \
    --error="logs/%j/%j-quantum.err" \
    quantum_step.sh)

# ── Create run directory keyed on job ID (consistent with sqd-mpi/sqd-gpu) ─
RUN_DIR="$(pwd)/runs/$JOB_ID"
mkdir -p "$RUN_DIR" "logs/$JOB_ID"
echo "$RUN_DIR" > "$(pwd)/run_dir"

# ── Initialise parameters and iteration counter ───────────────────────────
python3 - <<EOF
import numpy as np
from pathlib import Path

run_dir = Path("$RUN_DIR")
rng = np.random.default_rng(42)
params = rng.uniform(-np.pi, np.pi, 2)  # [beta[0], gamma[0]]
np.save(run_dir / "params.npy", params)
(run_dir / "iteration.txt").write_text("1")
print(f"Initial params: {params}")
EOF

echo "Submitted quantum step 1: job $JOB_ID"
echo "Monitor with:  watch squeue"
echo "Results in:    $RUN_DIR"
