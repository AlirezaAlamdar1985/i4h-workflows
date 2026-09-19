#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
PYTHON_EXECUTABLE=${PYTHON_EXECUTABLE:-$CONDA_PREFIX/bin/python}
HOLOSCAN_DIR=${1:-$PROJECT_ROOT/workflows/robotic_ultrasound/scripts/holoscan_apps/}

# ---- Install Holoscan ----
$PYTHON_EXECUTABLE -m pip install holoscan==2.9.0
echo "Holoscan installed successfully!"

# ---- Install Holoscan Apps ----
echo "Building Holoscan Apps..."
pushd $HOLOSCAN_DIR

# 1. Locate holoscanConfig.cmake anywhere inside the active environment
HOLOSCAN_CMAKE_FILE=$(find "$CONDA_PREFIX" /venv/robotic_ultrasound -name "*holoscan*Config*.cmake" 2>/dev/null | head -n 1)

if [ -z "$HOLOSCAN_CMAKE_FILE" ]; then
    echo "ERROR: Could not locate holoscanConfig.cmake inside $CONDA_PREFIX or /venv/robotic_ultrasound!"
    exit 1
fi

HOLOSCAN_CMAKE_DIR=$(dirname "$HOLOSCAN_CMAKE_FILE")
echo "Found Holoscan CMake configuration at: $HOLOSCAN_CMAKE_DIR"

# 2. Clean previous build artifacts
rm -rf build clarius_solum/include clarius_solum/lib clarius_cast/include clarius_cast/lib

# 3. Configure and build
cmake -B build -S . \
  -Dholoscan_DIR="${HOLOSCAN_CMAKE_DIR}" \
  -DCMAKE_PREFIX_PATH="${HOLOSCAN_CMAKE_DIR};${CONDA_PREFIX}" \
  -DPYTHON_EXECUTABLE="${PYTHON_EXECUTABLE}"

cmake --build build

popd
echo "Holoscan Apps build completed!"