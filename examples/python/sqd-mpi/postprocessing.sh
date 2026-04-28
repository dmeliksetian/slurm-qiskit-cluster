#!/bin/bash
#SBATCH --job-name=sqd-mpi-postprocessing
#SBATCH --nodes=2                  # cluster has 2 nodes; round-robin handles NUM_BATCHES=3
#SBATCH --ntasks-per-node=1        # one MPI rank per node
#SBATCH --cpus-per-task=32         # threads for PySCF's internal parallelism
#SBATCH --output=logs/%j-postprocessing.out
#SBATCH --error=logs/%j-postprocessing.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

MAPPING_JOB_ID=$(cat "$SLURM_SUBMIT_DIR/mapping_job_id")
export RUN_DIR="${SLURM_SUBMIT_DIR}/runs/${MAPPING_JOB_ID}"
echo "RUN_DIR=$RUN_DIR"

# OMP_NUM_THREADS lets PySCF/solve_sci_batch use all cores on each node.
# Combined with MPI across nodes this gives two levels of parallelism:
#   MPI rank  → one batch per rank (inter-node)
#   OMP thread → Davidson eigensolver parallelism (intra-node)
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

mpirun --allow-run-as-root python -u /shared/examples/python/sqd-mpi/postprocessing.py
