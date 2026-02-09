# Pixel 8 / 8 Pro Kernel (KernelSU + SUSFS)

Kernel with KernelSU and SUSFS integration. Designed for stock firmware.

### ⚠️ Warning

> **Anything you do with your device is at your own risk.**

Even though I personally test it on my Pixel 8, I provide no guarantees whatsoever. By default, this kernel should be treated as something that **will harm your device and wipe all your data**. You have been warned ‼️

Make full backups of your data and keep them in a safe place. Also, backup partitions that cannot be restored without a pre-existing backup, such as: `persist`, `efs`, `efs_backup`, `devinfo`, etc.

---

### Features
* KernelSU-Next with KPatch-Next / KernelSU
* SUSFS
* Baseband-guard

### Build Information

Kernel version, KSU version, and other info can be found in the [releases](#).

Build tools and external kernel modules are taken from the GrapheneOS repository. This is because Google has stopped updating repositories for our devices.

Some critical drivers are integrated directly into the kernel rather than as external modules (for this reason, pure GKI kernels are not suitable for us). I consider using outdated drivers and tools unacceptable, so as a compromise, I chose to use what the GrapheneOS team offers in their kernels.

**Current structure:**
*   Tools and drivers from the GrapheneOS repository.
*   Adaptation patches.
*   AOSP kernel code (GKI) from Google.

> I build this kernel strictly for personal use. Support will be provided only as long as I need it and/or have the desire to do so.

### Credits

*   **SUSFS:** [gitlab.com/simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)
*   **KernelSU:** [github.com/tiann/KernelSU](https://github.com/tiann/KernelSU)
*   **KPatch-Next:** https://github.com/KernelSU-Next/KPatch-Next
*   **GrapheneOS:** [gitlab.com/grapheneos/kernel_pixel](https://gitlab.com/grapheneos/kernel_pixel)
*   **WildKernels:** [github.com/WildKernels](https://github.com/WildKernels)
*   **Baseband-guard:** https://github.com/vc-teahouse/Baseband-guard