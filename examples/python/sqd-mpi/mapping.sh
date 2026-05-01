#!/bin/bash
#SBATCH --job-name=sqd-mpi-mapping
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%j-mapping.out
#SBATCH --error=logs/%j-mapping.err

cd "$SLURM_SUBMIT_DIR"
mkdir -p "logs/$SLURM_JOB_ID"
source /shared/pyenv/bin/activate

# This is the first step — it owns RUN_DIR creation.
# All downstream steps derive their RUN_DIR from this job's ID.
export RUN_DIR="${SLURM_SUBMIT_DIR}/runs/${SLURM_JOB_ID}"
mkdir -p "$RUN_DIR"
echo "$SLURM_JOB_ID" > "$SLURM_SUBMIT_DIR/mapping_job_id"
echo "RUN_DIR=$RUN_DIR"

python -u /shared/examples/python/sqd-mpi/mapping.py
