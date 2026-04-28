#!/bin/bash
# submit.sh — Submit the full SQD workflow as a SLURM job chain.

set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
echo "Starting SQD Workflow Submission..."

# 1. Mapping
MAPPING_ID=$(sbatch --parsable mapping.sh)
if [ $? -ne 0 ]; then echo "Error submitting Mapping job."; exit 1; fi
echo "  [1/4] Mapping submitted:        $MAPPING_ID"

# 2. Optimization
OPTIMIZE_ID=$(sbatch --parsable \
    --dependency=afterok:$MAPPING_ID \
    optimization.sh)
if [ $? -ne 0 ]; then echo "Error submitting Optimization job."; exit 1; fi
echo "  [2/4] Optimization submitted:   $OPTIMIZE_ID (after $MAPPING_ID)"

# 3. Execution
EXECUTE_ID=$(sbatch --parsable \
    --dependency=afterok:$OPTIMIZE_ID \
    execution.sh)
if [ $? -ne 0 ]; then echo "Error submitting Execution job."; exit 1; fi
echo "  [3/4] Execution submitted:      $EXECUTE_ID (after $OPTIMIZE_ID)"

# 4. Postprocessing
POSTPROCESSING_ID=$(sbatch --parsable \
    --dependency=afterok:$EXECUTE_ID \
    postprocessing.sh)
if [ $? -ne 0 ]; then echo "Error submitting Postprocessing job."; exit 1; fi
echo "  [4/4] Postprocessing submitted: $POSTPROCESSING_ID (after $EXECUTE_ID)"

echo "------------------------------------------------"
echo "Full chain submitted. Monitor with: watch squeue"
