# RAMBO NES Emulator - Quick Start Guide

**Version:** 0.1.0 (Pre-release)
**Platform:** Linux (Wayland only)
**Last Updated:** 2025-10-07

---

## Prerequisites

### System Requirements

**Operating System:**
- Linux with Wayland compositor
- Tested on: Arch Linux, Ubuntu 24.04+

**Hardware:**
- CPU: Any x86_64 processor
- RAM: 512 MB minimum
- GPU: Vulkan 1.4+ support required

**Software:**
- Zig 0.15.1
- Wayland compositor (GNOME Wayland, KDE Plasma 6, Sway, Hyprland)
- Vulkan drivers for your GPU

### Installing Dependencies

**Arch Linux:**
```bash
# Zig
sudo pacman -S zig

# Wayland
sudo pacman -S wayland

# Vulkan
sudo pacman -S vulkan-headers vulkan-icd-loader

# GPU drivers (choose one):
sudo pacman -S vulkan-intel      # Intel
sudo pacman -S nvidia            # NVIDIA
sudo pacman -S vulkan-radeon     # AMD
```

**Ubuntu/Debian:**
```bash
# Zig 0.15.1 (manual install)
wget https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz
tar xf zig-linux-x86_64-0.15.1.tar.xz
sudo mv zig-linux-x86_64-0.15.1 /opt/zig
echo 'export PATH=/opt/zig:$PATH' >> ~/.bashrc
source ~/.bashrc

# Wayland and Vulkan
sudo apt install libwayland-dev libvulkan-dev vulkan-tools

# GPU drivers (choose one):
sudo apt install mesa-vulkan-drivers  # Intel/AMD
sudo apt install nvidia-driver         # NVIDIA
```

### Verify Installation

```bash
# Check Zig
zig version
# Should output: 0.15.1

# Check Wayland
echo $WAYLAND_DISPLAY
# Should output: wayland-1 (or similar)

# Check Vulkan
vulkaninfo | grep "apiVersion"
# Should show Vulkan 1.4+

# Check GPU drivers
ls /usr/lib/libvulkan.so
# Should exist
```

---

## Building RAMBO

### Clone Repository

```bash
cd ~/Development
git clone [repository-url] RAMBO
cd RAMBO
```

### Build

```bash
# Build release binary (optimized)
zig build -Doptimize=ReleaseFast

# OR build debug binary (with validation layers)
zig build -Doptimize=Debug

# Binary location:
# ./zig-out/bin/RAMBO
```

### Run Tests (Optional)

```bash
# Run all tests (~30 seconds)
zig build test

# Adapt this pattern to run singular tests, this is simply an example.
zig test --dep RAMBO  -Mroot=tests/integration/mmc3_visual_regression_test.zig -MRAMBO=src/root.zig -ODebug 

# Short form (via build system)
zig build test-integration

# Target specific tests by filter, in this ppu, and return a summary of the tests outcomes based on criteria.
zig build test --summary { all | failures | success } -- ppu
```

---

## Running RAMBO

### Basic Usage

```bash
# From RAMBO directory
./zig-out/bin/RAMBO path/to/rom.nes

# Example with AccuracyCoin test ROM:
./zig-out/bin/RAMBO AccuracyCoin/AccuracyCoin.nes
```

### Command Line Options

```bash
# Show help
./zig-out/bin/RAMBO --help

# Enable debug logging
./zig-out/bin/RAMBO --verbose path/to/rom.nes

# Disable vsync (for performance testing)
./zig-out/bin/RAMBO --no-vsync path/to/rom.nes
```

---

## Controls

### Keyboard Mapping

| NES Button | Keyboard Key |
|------------|--------------|
| D-Pad Up | ↑ Arrow Up |
| D-Pad Down | ↓ Arrow Down |
| D-Pad Left | ← Arrow Left |
| D-Pad Right | → Arrow Right |
| A Button | X |
| B Button | Z |
| Select | Right Shift |
| Start | Enter |

### Additional Controls

| Action | Key |
|--------|-----|
| Exit Emulator | ESC or close window |
| (More controls coming soon) | - |

---

## Loading ROM Files

### Supported ROM Formats

- **iNES (.nes files)**
  - Most common NES ROM format
  - Header identifies mapper type

### Supported Mappers

**Currently Supported:**
- **Mapper 0 (NROM)** - ~5% of NES library
  - Examples: Donkey Kong, Balloon Fight, Ice Climber

**Coming Soon:**
- Mapper 1 (MMC1) - +28% coverage
- Mapper 2 (UxROM) - +11% coverage
- Mapper 3 (CNROM) - +6% coverage
- Mapper 4 (MMC3) - +25% coverage

### Finding ROMs

**Legal Options:**
- Dump your own cartridges (requires hardware)
- Public domain ROMs (homebrew games)
- Test ROMs (AccuracyCoin, etc.)

**Note:** RAMBO does not include any ROM files. You must provide your own legal copies.

---

## Expected Behavior

### Startup

1. Window appears: "RAMBO NES Emulator" (512×480)
2. ROM loads and emulation starts
3. Frame rendering begins (should see graphics within 1 second)

### Performance

- **Target:** 60 FPS
- **Typical:** 60 FPS with vsync
- **CPU Usage:** 2-3% (modern CPU)
- **GPU Usage:** 1-2% (minimal load)

### Audio

**Note:** Audio is not yet implemented. Games will be silent.

---

## Troubleshooting

### Window Doesn't Open

**Problem:** "Error: Unable to connect to Wayland compositor"

**Solutions:**
1. Check Wayland is running:
   ```bash
   echo $WAYLAND_DISPLAY
   # Should output: wayland-1
   ```

2. If using X11, switch to Wayland:
   ```bash
   # Log out, select "GNOME (Wayland)" or "Plasma (Wayland)" at login
   ```

3. For headless systems, Wayland won't work (requires display server)

### Vulkan Errors

**Problem:** "Failed to create Vulkan instance"

**Solutions:**
1. Install Vulkan drivers:
   ```bash
   # Arch
   sudo pacman -S vulkan-intel vulkan-radeon  # or nvidia

   # Ubuntu
   sudo apt install mesa-vulkan-drivers
   ```

2. Verify Vulkan works:
   ```bash
   vulkaninfo | head -20
   # Should show device info
   ```

### ROM Won't Load

**Problem:** "Error loading ROM" or "Unsupported mapper"

**Solutions:**
1. Verify ROM file exists and is readable:
   ```bash
   file path/to/rom.nes
   # Should say: "NES ROM"
   ```

2. Check mapper number:
   ```bash
   # First 16 bytes of ROM
   xxd -l 16 path/to/rom.nes
   # Byte 6 (7th byte) bits 4-7 = mapper number low nibble
   ```

3. Currently only Mapper 0 supported. If ROM uses different mapper, it won't work yet.

### Game Renders Black Screen

**Known Issue:** Some commercial ROMs currently don't enable rendering (PPUMASK=$00).

**Status:** Under investigation.

**Workaround:** Try test ROMs like AccuracyCoin.nes (known working).

### Performance Issues

**Problem:** Low FPS or stuttering

**Solutions:**
1. Check CPU usage:
   ```bash
   top  # Look for RAMBO process
   # Should be <5% CPU
   ```

2. Disable vsync for testing:
   ```bash
   ./zig-out/bin/RAMBO --no-vsync path/to/rom.nes
   ```

3. Build release binary:
   ```bash
   zig build -Doptimize=ReleaseFast
   ```

### Threading Test Failures

**Problem:** "2/3 threading tests failed" when running `zig build test`

**Status:** Known issue - timing-sensitive tests

**Impact:** None (doesn't affect emulator functionality)

**Workaround:** Ignore if other 897+ tests pass

---

## Next Steps

### After Basic Testing

1. **Try Different ROMs:**
   - Test with multiple Mapper 0 games
   - Report which games work/don't work

2. **Adjust Settings:**
   - Try different window sizes
   - Test with/without vsync

3. **Contribute:**
   - Report bugs
   - Test on different hardware
   - Submit patches

### Learning More

**Documentation:**
- `README.md` - Project overview
- `CLAUDE.md` - Complete development guide
- `docs/CURRENT-STATUS.md` - Detailed status
- `docs/` - Full technical documentation

**Architecture:**
- `docs/architecture/` - System architecture
- `docs/implementation/` - Implementation details

---

## Known Limitations

**Current Version (0.1.0):**

1. **Mappers:** Only Mapper 0 (NROM) supported (~5% of games)
2. **Audio:** No sound output yet
3. **Save States:** Implemented but no UI yet
4. **Video:** No window resize, no fullscreen mode
5. **Input:** Keyboard only (no gamepad support)
6. **Platform:** Linux Wayland only (no X11, Windows, macOS)

**Coming Soon:**
- More mappers (MMC1, UxROM, CNROM, MMC3)
- Audio output
- Save state UI
- Gamepad support
- Additional platforms

---

## Getting Help

**Issues:**
1. Check this guide first
2. Check `docs/CURRENT-STATUS.md` for known issues
3. Search existing issues (if repository has issue tracker)
4. Create new issue with:
   - System info (`uname -a`, `vulkaninfo`)
   - ROM details (mapper number)
   - Error messages
   - Steps to reproduce

**Community:**
- (Add community links when available)

---

## Quick Command Reference

```bash
# Build
zig build -Doptimize=ReleaseFast

# Test
zig build test

# Run
./zig-out/bin/RAMBO path/to/rom.nes

# Debug build
zig build -Doptimize=Debug

# Clean build
rm -rf zig-cache zig-out
zig build
```

---

**Ready to play!** Load a Mapper 0 ROM and start testing.

**Note:** This is pre-release software. Expect bugs and missing features. Your feedback helps improve RAMBO!
