"""
postprocessing.py — Step 4: GPU-accelerated SQD classical post-processing.

Hamiltonians are built and occupancy averaging is done on GPU via CuPy.
Arrays are converted to NumPy at the solve_sci_batch boundary since
ffsim/PySCF expects NumPy inputs.

Run on g1 with: python postprocessing.py
"""

import numpy as np
from qiskit.primitives import BitArray
from qiskit_addon_sqd.counts import bit_array_to_arrays
from qiskit_addon_sqd.fermion import SCIResult, solve_sci_batch, bitstring_matrix_to_ci_strs
from qiskit_addon_sqd.subsampling import postselect_by_hamming_right_and_left, subsample
from qiskit_addon_sqd.configuration_recovery import recover_configurations

from config import (
    COUNTS_FILE,
    N_MODES, NELEC,
    SAMPLES_PER_BATCH, NUM_BATCHES, MAX_ITERATIONS,
    SYMMETRIZE_SPIN, SEED, EXACT_ENERGY,
    build_hamiltonians,
)
from common import load_counts, get_logger

log = get_logger("postprocessing")

h1e, h2e = build_hamiltonians()

rng = np.random.default_rng(np.random.SeedSequence(SEED))
nelec_a, nelec_b = NELEC
spin_sq = 0.0 if SYMMETRIZE_SPIN else None

counts = load_counts(COUNTS_FILE)
bit_array = BitArray.from_counts(counts)
bitstring_matrix, probabilities = bit_array_to_arrays(bit_array)
log.info(f"Loaded counts from {COUNTS_FILE} | {NUM_BATCHES} batches | {MAX_ITERATIONS} iterations")

result_history = []
avg_occupancies = None

for iteration in range(MAX_ITERATIONS):

    if avg_occupancies is not None:
        bitstring_matrix, probabilities = recover_configurations(
            bitstring_matrix,
            probabilities,
            avg_occupancies,
            num_elec_a=nelec_a,
            num_elec_b=nelec_b,
            rand_seed=rng,
        )

    bs_mat_postsel, probs_postsel = postselect_by_hamming_right_and_left(
        bitstring_matrix,
        probabilities,
        hamming_right=nelec_a,
        hamming_left=nelec_b,
    )

    all_batches = subsample(
        bs_mat_postsel, probs_postsel, SAMPLES_PER_BATCH, NUM_BATCHES, rand_seed=rng
    )

    results: list[SCIResult] = []
    for i in range(NUM_BATCHES):
        ci_strs = [bitstring_matrix_to_ci_strs(all_batches[i])]
        batch_results = solve_sci_batch(ci_strs, h1e, h2e, norb=N_MODES, nelec=NELEC, spin_sq=spin_sq)
        result = batch_results[0]
        results.append(result)
        log.info(
            f"iter {iteration + 1}/{MAX_ITERATIONS} | "
            f"batch {i} | energy {result.energy:.6f}"
        )

    result_history.append(results)

    avg_occupancies = (
        np.mean([res.orbital_occupancies[0] for res in results], axis=0),
        np.mean([res.orbital_occupancies[1] for res in results], axis=0),
    )


# Final reporting
min_es = [
    min(results, key=lambda r: r.energy).energy
    for results in result_history
]
min_id, min_e = min(enumerate(min_es), key=lambda x: x[1])

print(f"\nExact energy:   {EXACT_ENERGY:.5f}")
print(f"SQD energy:     {min_e:.5f}  (iteration {min_id + 1})")
print(f"Absolute error: {abs(min_e - EXACT_ENERGY):.5f}")
