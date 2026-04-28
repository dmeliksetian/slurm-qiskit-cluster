import os
from dotenv import load_dotenv
from qiskit import qpy
from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager
from qrmi.primitives import QRMIService
from qrmi.primitives.ibm import get_target, get_backend

data_folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(data_folder, exist_ok=True)

with open(os.path.join(data_folder, "circuits.qpy"), "rb") as f:
    circuits = qpy.load(f)

load_dotenv()
service = QRMIService()
resources = service.resources()
if len(resources) == 0:
    raise ValueError("No quantum resource is available.")

qrmi = resources[0]
target = get_target(qrmi)
backend = get_backend(qrmi)


pass_manager = generate_preset_pass_manager(
    optimization_level=3,
    backend=backend,
)

isa_circuits = pass_manager.run(circuits)

with open(os.path.join(data_folder, "isa_circuits.qpy"), "wb") as f:
    qpy.dump(isa_circuits, f)


print(isa_circuits[0].draw(scale=0.4))
