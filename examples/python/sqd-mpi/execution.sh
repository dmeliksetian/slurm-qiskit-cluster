#!/bin/bash
#SBATCH --job-name=sqd-mpi-execution
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=quantum
#SBATCH --gres=qpu:1
#SBATCH --qpu=ibm_marrakesh
#SBATCH --output=logs/%j-execution.out
#SBATCH --error=logs/%j-execution.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

MAPPING_JOB_ID=$(cat "$SLURM_SUBMIT_DIR/mapping_job_id")
export RUN_DIR="${SLURM_SUBMIT_DIR}/runs/${MAPPING_JOB_ID}"
echo "RUN_DIR=$RUN_DIR"

python -u /shared/examples/python/sqd-mpi/execution.py
