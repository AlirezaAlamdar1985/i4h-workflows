# Problems Encountered and Resolutions

Six issues hit while setting up and running the Robotic Ultrasound workflow. Each is stated as: what the issue
was, how it was diagnosed, how it was resolved, and what would be investigated next if it could not have been
resolved. The six code/config fixes these produced are listed together in `SETUP.md`; this document is the
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

## 5. The simulation appeared to "freeze," with GPU usage dropping to zero

**Issue:** After starting the simulation, the robot would move briefly, then stop entirely, with GPU utilization
falling to zero and no further activity.

**Diagnosis:** Reading the simulation's control loop showed it deliberately blocks, waiting for a reply from the
policy process over DDS, whenever it has no queued actions left to execute — this is correct behavior when no
policy is running, when a firewall is blocking the DDS network traffic, or while the policy is still loading its
model checkpoint, and is easy to mistake for a crash.

**Resolution:** Opened the required firewall ports for DDS's multicast traffic and confirmed the policy process
was actually running.

**Next if unresolved:** Run both processes in verbose mode and inspect the relevant DDS topic's traffic directly
(a DDS monitoring tool, or a packet capture on the multicast address) to confirm messages are actually reaching
the network, and check for a mismatched DDS domain ID between the two processes.

## 6. A rented VM crashed and rebooted mid-session

**Issue:** An SSH session and the remote desktop both became unresponsive, and the instance later showed signs of
having restarted.

**Diagnosis:** The current boot's kernel log showed nothing relevant — the crash had happened during the
*previous* boot, whose log had to be checked separately, since it does not appear in the default log view. That
log showed repeated GPU watchdog timeout messages immediately before the crash, indicating a GPU hardware/driver
hang rather than, for example, an out-of-memory condition or a clean shutdown.

**Resolution:** None available from inside the VM. Work continued on the same instance once it came back up; the
underlying cause (host, driver, or hardware) was never established.

**Next if unresolved:** This is the one issue without a real resolution. The next step would be reporting the
exact timestamps and kernel log contents to the hosting provider's support team, and renting a different
instance — a GPU hardware/driver hang is not something fixable from inside a guest VM.
