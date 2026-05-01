#!/bin/bash
#SBATCH --job-name=qaoa-quantum
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --partition=gpu_only
#SBATCH --nodelist=g1
#SBATCH --gres=gpu:1
#SBATCH --output=logs/%j-quantum.out
#SBATCH --error=logs/%j-quantum.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

export RUN_DIR=$(cat "$SLURM_SUBMIT_DIR/run_dir")
LOG_DIR="$SLURM_SUBMIT_DIR/logs/$(basename $RUN_DIR)"

python -u /shared/examples/python/qaoa/quantum_step.py

# Chain to classical step — runs only if this job succeeds
sbatch \
    --dependency=afterok:$SLURM_JOB_ID \
    --output="$LOG_DIR/%j-classical.out" \
    --error="$LOG_DIR/%j-classical.err" \
    /shared/examples/python/qaoa/classical_step.sh
