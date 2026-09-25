# Robotic Ultrasound: Docker on a Vast.ai Desktop VM Runbook

Steps that worked to build the Docker image and run the Robotic Ultrasound workflow
(Isaac Sim 5.1, Isaac Lab 2.3) with a visible Isaac Sim window, on a rented Vast.ai
**Ubuntu Desktop (VM)** instance. Branch: `docker-v0.5.0` (based on `v0.5.0`).

Verified: `sim_env` and the full pipeline run on an RTX 5090 (driver 580.105).
Not verified: the Clarius hardware modes, and raysim on cards other than the 5090.

## 1. Rent

- Template: **Ubuntu Desktop (VM)**. The container-based desktop templates run an `Xvfb` display, and
  Vulkan presenting depends on the host there, so the Isaac Sim window is not reliable.
- GPU: RTX class, 16 GB VRAM or more (5090 worked). Driver 580 or newer.
- Disk: **200 GB or more**. The image export peaked at 95% of a 146 GB disk.
- RAM: 64 GB or more.

## 2. Check display and Docker (2 minutes, before installing anything)

The desktop's Xorg is protected by an auth file, so a root SSH shell needs `XAUTHORITY`.
The file name changes on every boot.

```bash
export DISPLAY=:0                                       # check `ls /tmp/.X11-unix` if this fails
export XAUTHORITY=$(ls -d /var/run/sddm/{* | head -1)   # or take the path after -auth from: ps aux | grep [X]org
nvidia-smi                                              # want Xorg in the Processes list, type G
apt-get update && apt-get install -y x11-utils mesa-utils vulkan-tools tmux
xdpyinfo -display $DISPLAY | grep -i NV-GLX             # want a match
glxinfo -B | grep "OpenGL renderer"                     # want NVIDIA, not llvmpipe
vkcube --c 100; echo "exit=$?"                          # want exit=0
docker info | grep -i "Docker Root Dir"; df -h /
```

If `vkcube` fails ("Could not find both graphics and present queues") or the renderer is
`llvmpipe`, destroy the instance and rent another.

## 3. Docker with GPU support (NVIDIA Container Toolkit)

The VM template is described as shipping Docker with GPU support. Check first:

```bash
docker --version
docker info | grep -iE "runtimes|default runtime"      # want "nvidia" in Runtimes
docker run --rm --gpus all --runtime=nvidia nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

If the last command prints the GPU table, skip to section 4. Otherwise install the NVIDIA Container
Toolkit, following the
[NVIDIA install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
(Ubuntu/Debian with apt; run as root, or prefix `sudo`). Docker Engine itself must already be installed.

```bash
# prerequisites
apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg2

# production repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update

# install (the guide also shows how to pin a version with NVIDIA_CONTAINER_TOOLKIT_VERSION)
apt-get install -y nvidia-container-toolkit

# register the nvidia runtime with Docker and restart it
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# verify
docker run --rm --gpus all --runtime=nvidia nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

`./i4h` starts containers with `--runtime nvidia`, so the runtime must be registered with Docker.
If `--runtime=nvidia` still fails, see the Troubleshooting section of `docker/README.md`
(`daemon.json` with the nvidia runtime).

Do this section **before** starting the image build. `systemctl restart docker` interrupts a build that is
still running, including its final export step. The build itself does not need the GPU runtime (only running
the image does), but restarting Docker mid-build can leave you without an image.

## 4. Get the repo and the RTI license

```bash
cd ~ && git clone https://github.com/AlirezaAlamdar1985/i4h-workflows.git
cd i4h-workflows && git checkout docker-v0.5.0
mkdir -p rti && nano rti/rti_license.dat   # then paste the content and alt-x, yes
```

`./i4h` finds the license at `rti/rti_license.dat` in the repo root (`~/i4h-workflows/rti/`, next to the
`i4h` script, not in your home directory) and mounts it into the container. To keep it elsewhere, set
`RTI_LICENSE_FILE=/path/to/rti_license.dat` before running `./i4h`. The file is
gitignored (`*.dat`).

## 5. Build the image (about 30 minutes)

```bash
tmux new -s build
```
and then

```bash
docker build -f workflows/robotic_ultrasound/docker/Dockerfile -t robotic_us:latest . 2>&1 | tee build.log
```

- About 18 minutes for the setup layer (Isaac Sim, Isaac Lab, policies, Holoscan, raysim) and about 12 for the export.
- In a second tmux window run `watch -n 5 df -h /`. The export needs a large temporary amount of space.
  Stop the build if `Avail` drops below about 5 GB.
- Remove old images first (`docker images`, `docker rmi <image>`) if the disk is not empty.
- Do not run `docker builder prune` between attempts: it deletes the cached setup layer.

## 6. Tag the image for the `./i4h` CLI

```bash
docker tag robotic_us:latest i4h_build-robotic_ultrasound:docker-v0-5-0
```

The tag is `i4h_build-<workflow>:<branch>` with dots in the branch name turned into dashes. On a
different branch, retag (find the expected name with `./i4h run robotic_ultrasound sim_env --as-root --dryrun`).

## 7. Run

The simulation, policy and visualization talk to each other over DDS (RTI Connext), which uses UDP multicast.
Allow it through the firewall once per VM, before starting anything:

```bash
ufw allow in proto udp to 239.255.0.1 port 7400:7401
ufw allow out proto udp to 239.255.0.1 port 7400:7401
```

By default `./i4h run` rebuilds the container image on every run. Turn that off once, permanently for this VM
(the CLI reads `HOLOHUB_ALWAYS_BUILD`):

```bash
echo 'export HOLOHUB_ALWAYS_BUILD=false' >> ~/.bashrc
source ~/.bashrc
```

With it set, `--no-docker-build` is no longer needed (the commands below still show it, which is harmless).
To let the CLI build for a single run, use `HOLOHUB_ALWAYS_BUILD=true ./i4h run ...`.

Then start the workflow:

```bash
export DISPLAY=:0
export XAUTHORITY=$(ls -d /var/run/sddm/{* | head -1)

# simulation
./i4h run robotic_ultrasound sim_env --as-root --no-docker-build 2>&1 | tee run.log
# in a second terminal or tmux window:
./i4h run robotic_ultrasound pi0_policy --as-root --no-docker-build
./i4h run robotic_ultrasound visualization --as-root --no-docker-build
# or everything in one container:
./i4h run robotic_ultrasound full_pipeline --as-root --no-docker-build
```

- `./i4h modes robotic_ultrasound` lists the available modes.
- `./i4h ... --dryrun` prints the `docker run` command without running it.
- The first run downloads assets and checkpoints into `.cache/` in the repo folder (the container uses
  `HOME=/workspace/i4h`, which is the mounted repo). Watch `df -h /`.

## 8. Stopping

The terminal running a mode is attached to the container. Stop it from another terminal:

```bash
docker ps
docker stop <CONTAINER_ID>                # graceful
docker kill $(docker ps -q)               # forced, all running containers
```

A process stuck in state `T` (from Ctrl-Z) ignores a plain `kill`. Use `kill -9 <PID>`.

## Problems met and their fixes

| Symptom | Cause | Fix |
|---|---|---|
| `Authorization required, but no authorization protocol specified` from `xdpyinfo` or `vkcube` | SSH shell has no X auth | Set `XAUTHORITY` as in section 2 |
| Simulation, policy and visualization do not communicate | The firewall blocks the DDS multicast traffic | Allow UDP 7400:7401 to 239.255.0.1 with `ufw` (section 7) |
| VM freezes, sessions drop, then it reboots (`last -x` shows `crash`) | GPU hang. The previous boot's `journalctl -b -1 -k` shows `NVRM: krcWatchdog_IMPL: RC watchdog: GPU is probably locked!` and `nvidia-modeset: Error while waiting for GPU progress` (seen once on an RTX 5090, driver 580.105.08). `dmesg` alone only covers the current boot | Nothing to fix inside the VM. Watch with `journalctl -k -f \| grep -iE "NVRM\|Xid\|nvidia-modeset"`. If it recurs, rent another host and give the timestamps to Vast.ai support |
| `Failed to find a graphics and/or presenting queue` (Kit) | The display cannot present Vulkan (`Xvfb` on container templates) | Use the VM template, check with `vkcube` |
| `can't open file .../utilities/cli/holohub.py` | Unpinned HoloHub CLI downloaded `main`, which moved the CLI into the `holoscan-cli` package (HoloHub #1583, June 2026) | `i4h` pins HoloHub commit `913dcffa7c0f959281e7e4185158ec7c58c5f79f`. Override with `CLI_PINNED_COMMIT=...`. An empty stale `tools/utilities` is only re-downloaded when `CLI_FORCE_UPDATE=1` |
| `import pysolum`: `undefined symbol: solumDefaultInitParams` | `pysolum` was not linked against `libsolum.so` | `target_link_libraries` and an `$ORIGIN` rpath in `clarius_solum/CMakeLists.txt` |
| raysim build: `Use cmake.version instead of cmake.minimum-version` | v0.4.0 `pyproject.toml` uses an old key that scikit-build-core 0.8 or newer rejects | Guarded `sed` patch in `install_raysim.sh` |
| `Unknown CMake command "add_holohub_application"` in the Holoscan step | The standalone build in `install_holoscan.sh` never worked | Harmless: it fails inside an `&&` chain under `set -e`, and the Clarius libraries are built by `install_clarius.sh` |
| `module 'warp.types' has no attribute 'array'`, Kit extensions fail to load | `isaaclab` does not pin `warp-lang`, so pip installed 1.17.0. Isaac Sim 5.1 needs Warp 1.8.x | Dockerfile installs `warp-lang==1.8.1` |
| `no space left on device` at image export | The second `chmod -R a+rX /opt/miniconda3` copied the whole conda tree into a new layer | Removed that `chmod`; use a bigger disk |
| `/bin/bash: cannot execute binary file` (exit 126) | An image committed from a container started with `--entrypoint bash` kept `ENTRYPOINT ["bash"]` | Do not commit from such containers. Restore with `docker commit --change='ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]'` |

## Not verified yet

- Raysim on GPUs other than the 5090: `install_raysim.sh` builds with `-DCMAKE_CUDA_ARCHITECTURES=80`.
  If raytracing fails with "no kernel image", change it to `120` (5090) or `89` (4080).
- The Clarius modes (`clarius_cast`, `clarius_solum`): `./i4h` overrides `PYTHONPATH` in the container, which may
  drop the image's Clarius library paths.
- Other dependencies that are not pinned may drift between builds (pip resolves them at build time).
