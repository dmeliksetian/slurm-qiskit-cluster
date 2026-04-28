#!/bin/bash
#SBATCH --job-name=sqd-postprocessing
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=normal
#SBATCH --output=logs/%j-postprocessing.out
#SBATCH --error=logs/%j-postprocessing.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

python -u /shared/examples/python/sqd/postprocessing.py
