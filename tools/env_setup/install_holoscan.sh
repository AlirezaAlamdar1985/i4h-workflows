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

set -e

# Get the parent directory of the current script
# Assuming this script is in tools/env_setup/
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"

# Allow setting the python in PYTHON_EXECUTABLE
PYTHON_EXECUTABLE=${PYTHON_EXECUTABLE:-python}

HOLOSCAN_DIR=${1:-$PROJECT_ROOT/workflows/robotic_ultrasound/scripts/holoscan_apps/}

# ---- 1. Install Holoscan Python Bindings ----
$PYTHON_EXECUTABLE -m pip install holoscan==2.9.0
echo "Holoscan Python bindings installed!"

# ---- 2. Build Holoscan C++ Apps ----
echo "Building Holoscan Apps..."
pushd $HOLOSCAN_DIR

# 3. Clean previous build directory
rm -rf build
rm -rf clarius_solum/include
rm -rf clarius_solum/lib
rm -rf clarius_cast/include
rm -rf clarius_cast/lib

# 4. Configure CMake using the system C++ SDK path
cmake -B build -S . \
  -Dholoscan_DIR="/opt/nvidia/holoscan/lib/cmake/holoscan" \
  -DCMAKE_PREFIX_PATH="/opt/nvidia/holoscan;${CONDA_PREFIX}" \
  -DPYTHON_EXECUTABLE="${PYTHON_EXECUTABLE}"

cmake --build build

popd
echo "Holoscan Apps build completed!"
