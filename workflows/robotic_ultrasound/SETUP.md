# Setup Document: Robotic Ultrasound Workflow

Isaac for Healthcare's Robotic Ultrasound demo (Isaac Sim 5.1, Isaac Lab 2.3), built and run from a Docker image on
a rented cloud GPU VM. Verified working end to end — full pipeline (policy, simulation, ultrasound ray tracing,
visualization) — on an RTX 5090, driver 580.105.

## 1. Repository

```bash
git clone https://github.com/AlirezaAlamdar1985/i4h-workflows.git
cd i4h-workflows && git checkout docker-v0.5.0
```

This branch is based on the upstream `v0.5.0` release tag, with a small set of fixes on top — see
"Compatibility and configuration issues" below for the complete list and why each was needed.

## 2. Host requirements

- A cloud GPU instance with a **real, GPU-backed display** (not a virtual/software display) — required for the
  Isaac Sim window and for Vulkan/OptiX rendering. Verify with `vkcube` before installing anything; if it cannot
  find a presenting queue, the display will not work for this workflow.
- NVIDIA GPU, 16 GB VRAM or more, driver 580+.
- Docker Engine with the NVIDIA Container Toolkit (`--gpus all --runtime=nvidia` must work).
- 200 GB or more disk (the image build's export step needs significant temporary space).
- 64 GB or more RAM, confirmed on the instance itself — cloud VM listings can advertise far more RAM than the
  instance actually receives.

## 3. NVIDIA GPU support in Docker

Check first:
```bash
docker run --rm --gpus all --runtime=nvidia nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```
If that fails, install the NVIDIA Container Toolkit per
[NVIDIA's install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html),
then `nvidia-ctk runtime configure --runtime=docker` and restart Docker.

## 4. RTI Connext DDS license

The workflow's simulation, policy, and visualization processes communicate over RTI Connext DDS and require a
license file. Place it at `rti/rti_license.dat` in the repository root (or point `RTI_LICENSE_FILE` at it).

DDS uses UDP multicast; if a firewall is active, allow it once:
```bash
ufw allow in proto udp to 239.255.0.1 port 7400:7401
ufw allow out proto udp to 239.255.0.1 port 7400:7401
```

## 5. Build the Docker image (~30 minutes)

```bash
docker build -f workflows/robotic_ultrasound/docker/Dockerfile -t robotic_us:latest .
docker tag robotic_us:latest i4h_build-robotic_ultrasound:docker-v0-5-0
```
The image installs Isaac Sim 5.1, Isaac Lab 2.3, the PI0 and GR00T N1 policy stacks, Holoscan, and the ultrasound
ray-tracing simulator (raysim).

## 6. Run

The workflow ships an `./i4h` CLI (from NVIDIA's HoloHub project) that builds and launches the container for a
given mode:
```bash
./i4h run robotic_ultrasound sim_env --as-root --no-docker-build          # simulation only
./i4h run robotic_ultrasound pi0_policy --as-root --no-docker-build       # policy, in a second terminal
./i4h run robotic_ultrasound teleop_with_ultrasound --as-root --no-docker-build   # manual control + ultrasound
./i4h run robotic_ultrasound full_pipeline --as-root --no-docker-build    # everything in one container
```
`./i4h modes robotic_ultrasound` lists all available modes; `./i4h run ... --dryrun` prints the underlying
`docker run` command without executing it.

## Compatibility and configuration issues encountered

Everything below is a real difference from the upstream `v0.5.0` release, required to get the workflow running in
this environment (six files changed in total; nothing else in the repository differs from `v0.5.0`).

| Component | Issue | Fix |
|---|---|---|
| HoloHub CLI (`i4h`) | Upstream HoloHub restructured its CLI after the `v0.5.0` release (moved out of `utilities/cli/holohub.py` into a separate package), so an unpinned CLI download fails outright | Pin `CLI_PINNED_COMMIT` to the HoloHub commit immediately before the `v0.5.0` release |
| Isaac Sim / Warp | `isaaclab` does not pin the `warp-lang` package, so pip resolves the latest version (1.17.0), which removed APIs Isaac Sim 5.1's own extensions import — Kit fails to start | Pin `warp-lang==1.8.1` in the Dockerfile |
| Docker image build | A redundant permission-fixing step copied the entire conda environment into a new image layer, doubling image size and causing "no space left on device" during export | Remove the redundant step |
| Clarius Solum Python binding | `pysolum` was not linked against its native library, so `import pysolum` failed with an undefined-symbol error | Add the missing library link and rpath in its CMake configuration |
| Raysim (ultrasound ray tracing) build | The pinned raysim release uses a build-system key that current `scikit-build-core` rejects | Patch the key during install (guarded, only applied if needed) |
| Ultrasound ray-tracing example | The vendored C++ ray tracer logs unconditionally at `info` level every simulation cycle, with no way to lower its verbosity from outside | Added a workflow mode that filters this output |

A separate short document lists the specific debugging issues encountered (symptom, diagnosis, resolution, and
what would be investigated next for any left unresolved).
