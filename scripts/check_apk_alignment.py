#!/usr/bin/env python3
"""Statically inspect the native libs in an APK: inventory + 16 KB alignment.

Android 15+ on 16 KB-page devices requires every shared library's PT_LOAD
segments to be 16 KB (0x4000) aligned, or the app crashes at dlopen — often
~1 second after launch, before any UI. Standard emulators use 4 KB pages and do
NOT reproduce this, but parsing the ELF program headers catches it without any
device. Also prints which plugin .so are bundled (per ABI), useful for triage.

Usage:  python3 scripts/check_apk_alignment.py <path-to.apk>
Exit:   3 if any PT_LOAD segment is aligned to less than 16 KB; 0 otherwise.
"""

import struct
import sys
import zipfile

PT_LOAD = 1
SIXTEEN_KB = 0x4000


def load_segment_aligns(data: bytes):
    """Return the list of PT_LOAD p_align values, or None if not an ELF."""
    if data[:4] != b"\x7fELF":
        return None
    ei_class = data[4]  # 1 = 32-bit, 2 = 64-bit
    endian = "<" if data[5] == 1 else ">"
    is64 = ei_class == 2
    if is64:
        e_phoff = struct.unpack_from(endian + "Q", data, 0x20)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 0x36)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 0x38)[0]
        type_off, align_off = 0x00, 0x30
    else:
        e_phoff = struct.unpack_from(endian + "I", data, 0x1C)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 0x2A)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 0x2C)[0]
        type_off, align_off = 0x00, 0x1C

    aligns = []
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(endian + "I", data, base + type_off)[0]
        if p_type != PT_LOAD:
            continue
        fmt = endian + ("Q" if is64 else "I")
        p_align = struct.unpack_from(fmt, data, base + align_off)[0]
        aligns.append(p_align)
    return aligns


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_apk_alignment.py <apk>", file=sys.stderr)
        return 2
    apk = sys.argv[1]
    bad = []
    print(f"== native libs in {apk} ==")
    with zipfile.ZipFile(apk) as z:
        sos = sorted(
            n for n in z.namelist() if n.startswith("lib/") and n.endswith(".so")
        )
        if not sos:
            print("  (no bundled native libs)")
        for name in sos:
            aligns = load_segment_aligns(z.read(name))
            if aligns is None:
                print(f"  {name}: not an ELF file?")
                continue
            min_align = min(aligns) if aligns else 0
            ok = min_align >= SIXTEEN_KB
            print(
                f"  {name}: LOAD align min=0x{min_align:x} "
                f"{'OK' if ok else '<< NOT 16 KB-ALIGNED'}"
            )
            if not ok:
                bad.append((name, min_align))
    print("====")
    if bad:
        print("16 KB ALIGNMENT PROBLEM — these libs can crash on a 16 KB-page")
        print("device (Android 15+) at dlopen, ~1s after launch:")
        for name, a in bad:
            print(f"  {name}  (align 0x{a:x})")
        return 3
    print("All bundled native libs are >= 16 KB aligned.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
