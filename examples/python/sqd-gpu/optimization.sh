#!/bin/bash
#SBATCH --job-name=sqd-gpu-optimization
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%j-optimization.out
#SBATCH --error=logs/%j-optimization.err
# Backend names differ by IBM Quantum instance and region: replace ibm_marrakesh with a name from your qrmi_config.json.
#SBATCH --qpu=ibm_marrakesh

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

MAPPING_JOB_ID=$(cat "$SLURM_SUBMIT_DIR/mapping_job_id")
export RUN_DIR="${SLURM_SUBMIT_DIR}/runs/${MAPPING_JOB_ID}"
echo "RUN_DIR=$RUN_DIR"

python -u /shared/examples/python/sqd-gpu/optimization.py
