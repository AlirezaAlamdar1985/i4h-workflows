# Problems Encountered and Resolutions

Five issues hit while setting up and running the Robotic Ultrasound workflow. Each is stated as: what the issue
was, how it was diagnosed, how it was resolved, and what would be investigated next if it could not have been
resolved. The code/config fixes these produced are listed together in `SETUP.md`; this document is the
debugging narrative behind them.

## 1. Warp version mismatch broke Isaac Sim's extensions

**Issue:** Isaac Sim failed to start, with `AttributeError: module 'warp.types' has no attribute 'array'` and
several related import errors across its core extensions.

**Diagnosis:** Checked the installed package version inside the built image with `pip show warp-lang`. It showed
1.17.0, whereas Isaac Sim 5.1's own extensions are built against Warp's 1.8.x API. Tracing the dependency chain
showed `isaaclab` does not pin `warp-lang`, so `pip` resolved the newest release available at build time.

**Resolution:** Pinned `warp-lang==1.8.1` explicitly in the Docker build.

**Next if unresolved:** Check Isaac Sim 5.1's own release notes or dependency manifest for the exact Warp version
it was built and tested against, rather than picking the latest 1.8.x release by assumption; report the missing
pin upstream against `isaaclab`.

## 2. No usable graphics window on one class of cloud instance

**Issue:** The Isaac Sim window failed to open on certain rented GPU instances, with `Failed to find a graphics
and/or presenting queue` from Vulkan.

**Diagnosis:** `vkcube` and `nvidia-smi` showed the instance's desktop was backed by `Xvfb`, a virtual display
with no path to present GPU-rendered frames — not a real GPU-backed X server, regardless of the GPU itself being
correctly detected and otherwise usable for compute.

**Resolution:** Moved to a virtual-machine-based instance type with a real Xorg session running on the GPU,
verified with the same `vkcube` check before installing anything further.

**Next if unresolved:** Ask the hosting provider directly which instance templates offer genuine GPU-backed X11
in a container (not all container-based desktop templates do); if none exist, fall back to running headless with
remote streaming instead of a local window.

## 3. Docker image build failed with "no space left on device"

**Issue:** The final step of the Docker image build (exporting the built layers) failed after consuming all
available disk space.

**Diagnosis:** Noticed a pip-install step that normally completes in seconds was instead taking around ten
minutes. Comparing image layer sizes (`docker history`) showed a redundant permission-fixing command
(`chmod -R` over the entire Conda installation) was copying that whole directory tree into a new image layer,
roughly doubling the image's size.

**Resolution:** Removed the redundant command (an earlier step in the build already sets the needed permissions)
and used a larger disk for the build.

**Next if unresolved:** Split the Dockerfile into more, smaller layers to isolate exactly which step is
ballooning; consider a build with a different compression backend (e.g. Docker Buildx's zstd support).

## 4. The workflow's own CLI tool stopped working

**Issue:** The `./i4h` command-line tool, used to build and run the workflow, failed outright with
`can't open file .../holohub.py`.

**Diagnosis:** This tool downloads part of its implementation from the upstream HoloHub project at run time.
Checking that project's git history showed its CLI had been restructured into a separate package after this
workflow's release was cut, so the workflow's unpinned download was fetching incompatible, newer code.

**Resolution:** Pinned the download to the HoloHub commit immediately preceding this workflow's release.

**Next if unresolved:** Vendor the specific CLI files this workflow actually needs directly into the repository,
rather than downloading them at run time, so a future upstream restructuring cannot break it again.

## 5. The ultrasound ray-tracing simulator failed to build

**Issue:** Installing the ultrasound ray-tracing component (a pinned third-party release) failed during its
Python package build, with `ERROR: Use cmake.version instead of cmake.minimum-version with scikit-build-core >= 0.8`.

**Diagnosis:** The pinned release's build configuration was written against an older version of the
`scikit-build-core` build backend, which used a `cmake.minimum-version` key. The current version of that backend,
resolved fresh at install time (it is not itself pinned), rejects that key outright in favor of a renamed
`cmake.version` key.

**Resolution:** Patched the one affected line in that build configuration (`cmake.minimum-version` →
`cmake.version`) as part of the install step, applied only when the old key is still present so the patch stays
harmless if the pinned release is ever updated.

**Next if unresolved:** Pin `scikit-build-core` itself to a version compatible with the old key, rather than
patching the third-party release's configuration; or report the incompatibility upstream to that release's
maintainers, since the underlying dependency (raysim) is not part of this repository.
