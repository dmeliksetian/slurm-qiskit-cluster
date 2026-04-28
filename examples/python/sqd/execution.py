import os
import json
from dotenv import load_dotenv
from qiskit import qpy
from qiskit.primitives import BitArray

from qrmi.primitives import QRMIService
from qrmi.primitives.ibm import SamplerV2


load_dotenv()
service = QRMIService()

data_folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(data_folder, exist_ok=True)

with open(os.path.join(data_folder, "isa_circuits.qpy"), "rb") as f:
    isa_circuits = qpy.load(f)


resources = service.resources()
if len(resources) == 0:
    raise ValueError("No quantum resource is available.")

qrmi = resources[0]

# Sample from the circuits
options = {
    "default_shots": 10000,
}
sampler = SamplerV2(qrmi, options=options)
job = sampler.run(isa_circuits)

# Combine the counts from the individual Trotter circuits
bit_array = BitArray.concatenate_shots([result.data.meas for result in job.result()])

counts = bit_array.get_counts()

with open(os.path.join(data_folder, "counts.json"), "w") as f:
    json.dump(counts, f)

print(counts)
