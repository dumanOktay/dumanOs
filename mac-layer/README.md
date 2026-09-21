# 🍏 dumanOS Mac Android Layer (duman-droid for macOS)

Native Android Runtime for Apple Silicon Mac (M1/M2/M3/M4) powered by Apple's `Virtualization.framework`, Metal graphics pipeline, and seamless macOS window integration.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       macOS Host                            │
│  ┌───────────────────────┐       ┌───────────────────────┐  │
│  │   dumanOS Menu Bar    │       │ Native Cocoa Windows  │  │
│  │     (Swift / App)     │       │  (Metal GPU Renderer) │  │
│  └───────────┬───────────┘       └───────────▲───────────┘  │
│              │                               │              │
│              │ Apple Virtualization.framework│ (Wayland/XPC)│
│  ┌───────────▼───────────────────────────────┴───────────┐  │
│  │       Micro-Linux Guest (ARM64 Native Execution)      │  │
│  │  - Tiny Linux Kernel with binder_linux + ashmem       │  │
│  │  - LXC Waydroid Container (100% Native ARM64 Speed)   │  │
│  │  - Google Play Services (GAPPS) + Multi-Window Mode   │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Key Highlights

1. **Zero Emulation Overhead:** Apple Silicon (ARM64) executes Android ARM64 binary code natively without CPU translation (100% CPU speed).
2. **Seamless Windows:** Android apps launch as native macOS floating windows that support macOS shortcuts, resizing, and dock icons.
3. **Ultra-Lightweight MicroVM:** Boots in under 1 second and consumes ~150-250 MB RAM at idle.
4. **Native Drag-and-Drop:** Drag any `.apk` file onto the macOS app window to install instantly.

---

## 📁 Directory Structure

* `core/`: Swift / Apple `Virtualization.framework` host application.
* `microvm/`: Micro-Linux kernel & Waydroid minimal image generator.
* `bridge/`: Wayland-to-Cocoa window surface bridge.
* `scripts/`: 1-click build and run utilities.
