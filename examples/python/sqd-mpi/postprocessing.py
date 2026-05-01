"""
postprocessing.py — Step 4: MPI-parallel SQD classical post-processing.

Each MPI rank handles a subset of the num_batches eigensolves.
Rank 0 handles configuration recovery, broadcasting, gathering,
logging, and final energy reporting.

Run with:
    OMP_NUM_THREADS=<cores_per_rank> mpiexec -n <num_batches> python postprocessing.py
"""

import numpy as np
from mpi4py import MPI
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

# ── MPI setup ──────────────────────────────────────────────────────────────
comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

log = get_logger(f"postprocessing[rank{rank}]")

# ── Batch assignment: round-robin stripe across ranks ──────────────────────
# e.g. NUM_BATCHES=3, size=2 → rank 0: [0, 2], rank 1: [1]
my_batch_indices = list(range(rank, NUM_BATCHES, size))
rank_batch_map = [list(range(r, NUM_BATCHES, size)) for r in range(size)]

# ── Unique seed per rank to avoid correlated samples ──────────────────────
ss = np.random.SeedSequence(SEED)
rng = np.random.default_rng(ss.spawn(size)[rank])

# ── Load inputs (all ranks need h1e/h2e; only rank 0 needs counts) ─────────
h1e, h2e = build_hamiltonians()
nelec_a, nelec_b = NELEC
spin_sq = 0.0 if SYMMETRIZE_SPIN else None

if rank == 0:
    counts = load_counts(COUNTS_FILE)
    bit_array = BitArray.from_counts(counts)
    bitstring_matrix, probabilities = bit_array_to_arrays(bit_array)
    log.info(
        f"Loaded counts from {COUNTS_FILE} | "
        f"{size} MPI ranks | {NUM_BATCHES} batches | "
        f"{MAX_ITERATIONS} iterations"
    )

# ── Main SQD loop ──────────────────────────────────────────────────────────
result_history = []
avg_occupancies = None

for iteration in range(MAX_ITERATIONS):

    # ── Config recovery and subsampling (rank 0 only) ──────────────────────
    if rank == 0:
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
    else:
        all_batches = None

    # Broadcast all batches from rank 0 to every rank
    all_batches = comm.bcast(all_batches, root=0)

    # ── Eigensolve: each rank works on its assigned batches ────────────────
    local_results: list[SCIResult] = []
    for batch_idx in my_batch_indices:
        ci_strs = [bitstring_matrix_to_ci_strs(all_batches[batch_idx])]
        results = solve_sci_batch(ci_strs, h1e, h2e, norb=N_MODES, nelec=NELEC, spin_sq=spin_sq)
        result = results[0]
        local_results.append(result)
        log.info(
            f"iter {iteration + 1}/{MAX_ITERATIONS} | "
            f"batch {batch_idx} | energy {result.energy:.6f}"
        )

    # ── Gather all results onto rank 0, preserving batch order ────────────
    all_local_results = comm.gather(local_results, root=0)

    if rank == 0:
        flat_results: list[SCIResult] = [None] * NUM_BATCHES
        for r, batch_indices in enumerate(rank_batch_map):
            for local_i, batch_idx in enumerate(batch_indices):
                flat_results[batch_idx] = all_local_results[r][local_i]

        result_history.append(flat_results)
        log.info(f"── Iteration {iteration + 1} ──")
        for i, res in enumerate(flat_results):
            log.info(
                f"  Subsample {i} | "
                f"energy {res.energy:.6f} | "
                f"subspace dim {np.prod(res.sci_state.amplitudes.shape)}"
            )

        avg_occupancies = (
            np.mean([res.orbital_occupancies[0] for res in flat_results], axis=0),
            np.mean([res.orbital_occupancies[1] for res in flat_results], axis=0),
        )

    avg_occupancies = comm.bcast(avg_occupancies if rank == 0 else None, root=0)


# ── Final reporting (rank 0 only) ──────────────────────────────────────────
if rank == 0:
    min_es = [
        min(results, key=lambda r: r.energy).energy
        for results in result_history
    ]
    min_id, min_e = min(enumerate(min_es), key=lambda x: x[1])

    print(f"\nExact energy:   {EXACT_ENERGY:.5f}")
    print(f"SQD energy:     {min_e:.5f}  (iteration {min_id + 1})")
    print(f"Absolute error: {abs(min_e - EXACT_ENERGY):.5f}")
