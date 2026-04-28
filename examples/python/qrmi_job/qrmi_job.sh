#!/bin/bash
#SBATCH --job-name=qrmi-job
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=quantum
#SBATCH --gres=qpu:1
#SBATCH --qpu=ibm_marrakesh
#SBATCH --output=logs/%j-qrmi-job.out
#SBATCH --error=logs/%j-qrmi-job.err

cd "$SLURM_SUBMIT_DIR"
mkdir -p logs
source /shared/pyenv/bin/activate

srun python -u /shared/examples/python/qrmi_job/qrmi_job.py
