"""
quantum_step.py — Step A: Evaluate QAOA circuits on GPU (AerSimulator).

For each iteration, evaluates the cost expectation value at the current
parameters plus all parameter-shifted points needed for the gradient:

  index 0       : E(θ)                 — current energy
  index 2i+1    : E(θ + π/2 · eᵢ)     — shift+ for param i
  index 2i+2    : E(θ - π/2 · eᵢ)     — shift- for param i

Total: 1 + 2 * N_PARAMS circuit evaluations per iteration.
Saves results to EXPECTATION_FILE for classical_step.py to consume.
"""

import numpy as np
from qiskit_aer.primitives import Estimator as AerEstimator

from config import (
    PARAMS_FILE, EXPECTATION_FILE, ITERATION_FILE,
    N_PARAMS, build_cost_operator, build_qaoa_circuit,
)
from common import get_logger, load_npy, save_npy

log = get_logger("quantum_step")

iteration = int(ITERATION_FILE.read_text().strip())
params = load_npy(PARAMS_FILE)
log.info(f"Iteration {iteration} | params: {params}")

# Build all parameter sets: current + shifts for parameter shift rule
shift = np.pi / 2
all_params = [params]
for i in range(N_PARAMS):
    p_plus  = params.copy(); p_plus[i]  += shift
    p_minus = params.copy(); p_minus[i] -= shift
    all_params.append(p_plus)
    all_params.append(p_minus)

log.info(f"Evaluating {len(all_params)} circuits on GPU")

cost_op = build_cost_operator()
circuit = build_qaoa_circuit()

estimator = AerEstimator()
estimator.set_options(device="GPU", method="statevector", shots=None)

job = estimator.run(
    [circuit] * len(all_params),
    [cost_op] * len(all_params),
    all_params,
)
evs = np.array(job.result().values)

log.info(f"E(θ) = {evs[0]:.6f}")
save_npy(EXPECTATION_FILE, evs)
log.info(f"Saved {len(evs)} expectation values to {EXPECTATION_FILE}")
