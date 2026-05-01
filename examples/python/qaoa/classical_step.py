"""
classical_step.py — Step B: Gradient computation and parameter update on GPU.

Reads the expectation values saved by quantum_step.py, computes the
parameter shift rule gradient using CuPy, applies an Adam update, then
either re-submits quantum_step.sh for the next iteration or reports
the final result if converged.

Parameter shift rule:
  ∂⟨C⟩/∂θᵢ = [E(θ + π/2 · eᵢ) - E(θ - π/2 · eᵢ)] / 2

We maximise ⟨C⟩ via gradient ascent, implemented as gradient descent
on the loss L = -⟨C⟩.
"""

import subprocess
from pathlib import Path

import cupy as cp
import numpy as np

from config import (
    RUN_DIR,
    PARAMS_FILE, EXPECTATION_FILE, ENERGY_HISTORY_FILE,
    ADAM_STATE_FILE, ITERATION_FILE,
    N_PARAMS, LEARNING_RATE, BETA1, BETA2, EPSILON,
    MAX_ITERATIONS, CONVERGENCE_TOL, MAX_CUT_VALUE,
)
from common import get_logger, load_npy, save_npy, load_json, save_json

log = get_logger("classical_step")

# ── Load state ─────────────────────────────────────────────────────────────
iteration = int(ITERATION_FILE.read_text().strip())
evs    = cp.asarray(load_npy(EXPECTATION_FILE))  # shape: (1 + 2*N_PARAMS,)
params = cp.asarray(load_npy(PARAMS_FILE))

current_energy = float(evs[0])
log.info(f"Iteration {iteration} | ⟨C⟩ = {current_energy:.6f} / {MAX_CUT_VALUE}")

# ── Parameter shift rule gradient (GPU) ───────────────────────────────────
# Gradient of loss L = -⟨C⟩:  ∂L/∂θᵢ = -[E(θ+π/2·eᵢ) - E(θ-π/2·eᵢ)] / 2
grad = cp.zeros(N_PARAMS)
for i in range(N_PARAMS):
    grad[i] = -(evs[2 * i + 1] - evs[2 * i + 2]) / 2.0

log.info(f"Gradient: {cp.asnumpy(grad)} | ||grad|| = {float(cp.linalg.norm(grad)):.6f}")

# ── Adam update (GPU) ──────────────────────────────────────────────────────
try:
    state = load_json(ADAM_STATE_FILE)
    m = cp.asarray(state["m"])
    v = cp.asarray(state["v"])
    t = state["t"]
except FileNotFoundError:
    m = cp.zeros(N_PARAMS)
    v = cp.zeros(N_PARAMS)
    t = 0

t += 1
m = BETA1 * m + (1 - BETA1) * grad
v = BETA2 * v + (1 - BETA2) * grad ** 2
m_hat = m / (1 - BETA1 ** t)
v_hat = v / (1 - BETA2 ** t)
new_params = params - LEARNING_RATE * m_hat / (cp.sqrt(v_hat) + EPSILON)

save_json(ADAM_STATE_FILE, {
    "m": cp.asnumpy(m).tolist(),
    "v": cp.asnumpy(v).tolist(),
    "t": t,
})

# ── Update history and params ──────────────────────────────────────────────
try:
    history = load_npy(ENERGY_HISTORY_FILE).tolist()
except FileNotFoundError:
    history = []
history.append(current_energy)
save_npy(ENERGY_HISTORY_FILE, np.array(history))

new_params_np = cp.asnumpy(new_params)
save_npy(PARAMS_FILE, new_params_np)
log.info(f"Updated params: {new_params_np}")

# ── Convergence check ──────────────────────────────────────────────────────
grad_norm = float(cp.linalg.norm(grad))
converged = grad_norm < CONVERGENCE_TOL or iteration >= MAX_ITERATIONS

if converged:
    reason = "gradient converged" if grad_norm < CONVERGENCE_TOL else "max iterations reached"
    best_energy = max(history)
    log.info(f"Stopping: {reason}")
    print(f"\nQAOA optimisation complete ({reason}):")
    print(f"  Iterations:     {iteration}")
    print(f"  Best ⟨C⟩:       {best_energy:.5f} / {MAX_CUT_VALUE}")
    print(f"  Approximation:  {best_energy / MAX_CUT_VALUE:.3f}")
    print(f"  Final params:   {new_params_np}")
    print(f"  Results in:     {RUN_DIR}")
else:
    # Submit next quantum step — classical_step is still running when it
    # submits, so no dependency needed; the new job queues immediately.
    next_iter = iteration + 1
    ITERATION_FILE.write_text(str(next_iter))

    log_dir = Path(__file__).parent / "logs" / RUN_DIR.name
    result = subprocess.run(
        [
            "sbatch",
            f"--output={log_dir}/%j-quantum.out",
            f"--error={log_dir}/%j-quantum.err",
            "quantum_step.sh",
        ],
        capture_output=True,
        text=True,
        cwd=Path(__file__).parent,
    )
    if result.returncode != 0:
        log.error(f"sbatch failed: {result.stderr.strip()}")
        raise RuntimeError("Failed to submit next quantum step")

    job_id = result.stdout.strip().split()[-1]
    log.info(f"Submitted quantum step {next_iter}: job {job_id}")
