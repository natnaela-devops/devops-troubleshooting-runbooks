# Repair UEFI boot entries and GRUB without breaking Windows dual boot

## Problem
A Linux/Windows dual-boot machine developed a bad or duplicated UEFI boot entry and unreliable Linux boot behavior.

## Investigation
Capture the current firmware state before changing anything:

```bash
sudo efibootmgr -v
lsblk -f
findmnt /boot/efi
```

Identify:
- the currently booted entry (`BootCurrent`),
- the Linux/GRUB entry,
- the Windows Boot Manager entry,
- stale or corrupted duplicates,
- the configured `BootOrder`.

## Recovery pattern
Remove only the confirmed stale firmware entry:

```bash
sudo efibootmgr -b <stale-id> -B
```

Reinstall GRUB to the existing EFI System Partition rather than formatting it:

```bash
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=<linux-id>
sudo update-grub
```

Then explicitly set a sane boot order while preserving Windows Boot Manager:

```bash
sudo efibootmgr -o <linux-id>,<windows-id>,<other-required-ids>
```

## Verification
```bash
sudo efibootmgr -v
```

Reboot and confirm:
- Linux boots through the intended entry,
- Windows remains available,
- `BootCurrent` matches the repaired Linux entry,
- no unwanted duplicate entry reappears.

## Safety
Never delete an EFI System Partition or Windows Boot Manager merely because GRUB is broken. Firmware entries and filesystem contents are different layers.

## Lesson
Repair dual-boot systems by first distinguishing UEFI NVRAM entries, the EFI filesystem, and GRUB configuration. A bad boot entry usually does not require repartitioning.