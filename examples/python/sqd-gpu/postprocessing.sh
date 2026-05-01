#!/bin/bash
#SBATCH --job-name=sqd-gpu-postprocessing
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --partition=gpu_only
#SBATCH --nodelist=g1
#SBATCH --gres=gpu:1
#SBATCH --output=logs/%j-postprocessing.out
#SBATCH --error=logs/%j-postprocessing.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

MAPPING_JOB_ID=$(cat "$SLURM_SUBMIT_DIR/mapping_job_id")
export RUN_DIR="${SLURM_SUBMIT_DIR}/runs/${MAPPING_JOB_ID}"
echo "RUN_DIR=$RUN_DIR"

python -u /shared/examples/python/sqd-gpu/postprocessing.py
