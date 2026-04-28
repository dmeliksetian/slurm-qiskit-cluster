#!/bin/bash
echo "export PATH=/shared/pyenv/bin:$PATH"

# WSL2 NVIDIA driver libs
_LD=/usr/lib/wsl/lib

# cuquantum/cutensor: needed by qiskit-aer GPU on qg1
_SP=/shared/pyenv/lib/python3.12/site-packages
for _pkg in cuquantum cutensor; do
    [ -d "${_SP}/${_pkg}/lib" ] && _LD="${_SP}/${_pkg}/lib:${_LD}"
done
unset _SP _pkg

echo "export LD_LIBRARY_PATH=${_LD}:$LD_LIBRARY_PATH"
unset _LD
