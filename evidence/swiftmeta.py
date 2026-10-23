#!/usr/bin/env python3
"""Extract Swift metadata (types + field names) from a Mach-O without a decompiler.

Reads the arm64 slice of a (possibly universal) Mach-O and dumps:
  - nominal type names from __swift5_types / __swift5_reflstr
  - field names + types from __swift5_fieldmd
The binary is stripped, so this is the only source of the real API surface.
"""
import struct
import sys

FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF


def read_file(path):
    with open(path, "rb") as fh:
        return fh.read()


def slice_arm64(buf):
    magic = struct.unpack_from(">I", buf, 0)[0]
    if magic != FAT_MAGIC:
        return buf, 0
    nfat = struct.unpack_from(">I", buf, 4)[0]
    for i in range(nfat):
        cpu, sub, off, size, align = struct.unpack_from(">IIIII", buf, 8 + i * 20)
        if cpu == 0x0100000C:  # CPU_TYPE_ARM64
            return buf[off:off + size], off
    raise SystemExit("no arm64 slice")


def sections(buf):
    """Return {segname,sectname} -> (file_offset, size, addr)."""
    magic = struct.unpack_from("<I", buf, 0)[0]
    if magic != MH_MAGIC_64:
        raise SystemExit("not a 64-bit Mach-O")
    ncmds = struct.unpack_from("<I", buf, 16)[0]
    off = 32
    out = {}
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = buf[off + 8:off + 24].split(b"\0")[0].decode()
            nsects = struct.unpack_from("<I", buf, off + 64)[0]
            so = off + 72
            for _ in range(nsects):
                sectname = buf[so:so + 16].split(b"\0")[0].decode()
                addr, size = struct.unpack_from("<QQ", buf, so + 32)
                fileoff = struct.unpack_from("<I", buf, so + 48)[0]
                out[(segname, sectname)] = (fileoff, size, addr)
                so += 80
        off += cmdsize
    return out


def cstrings(blob):
    """Split a null-terminated string blob into strings."""
    cur = bytearray()
    for b in blob:
        if b == 0:
            if cur:
                yield bytes(cur)
            cur = bytearray()
        else:
            cur.append(b)
    if cur:
        yield bytes(cur)


def relname(base, offset, addr):
    """Mangled relative name -> full mangled name with leading $s."""
    # base points at the '$s' of the referenced symbol; offset is the signed
    # 32-bit relative displacement stored in the descriptor.
    rel = struct.unpack_from("<i", blob32, offset)[0]
    target = base + rel
    idx = target - blob32_addr
    if idx < 0 or idx >= len(blob32):
        return None
    end = blob32.index(b"\0", idx)
    return blob32[idx:end].decode()


def main():
    path = sys.argv[1]
    buf = read_file(path)
    buf, slice_off = slice_arm64(buf)
    secs = sections(buf)

    refl = secs.get(("__TEXT", "__swift5_reflstr"))
    types = secs.get(("__TEXT", "__swift5_types"))
    fieldmd = secs.get(("__TEXT", "__swift5_fieldmd"))
    if not refl or not types:
        raise SystemExit("missing swift metadata sections")

    refl_blob = buf[refl[0]:refl[0] + refl[1]]
    names = set()
    for s in cstrings(refl_blob):
        try:
            names.add(s.decode("utf-8"))
        except UnicodeDecodeError:
            pass

    # __swift5_types holds RelativeDirectPointer pairs to nominal type
    # descriptors, which point at the mangled name string.
    tblob = buf[types[0]:types[0] + types[1]]
    mangled = set()
    for i in range(0, len(tblob) - 8, 8):
        rel, kind = struct.unpack_from("<iB", tblob, i)
        if kind != 0:  # only nominal type descriptors
            continue
        target = types[2] + i + rel
        idx = target - types[2]
        if idx < 0 or idx >= len(refl_blob):
            continue
        end = refl_blob.index(b"\0", idx)
        try:
            mangled.add(refl_blob[idx:end].decode("utf-8"))
        except UnicodeDecodeError:
            pass

    print("### reflstr strings: %d" % len(names))
    print("### nominal type descriptors: %d" % len(mangled))
    for m in sorted(mangled):
        print(m)

    if fieldmd:
        fblob = buf[fieldmd[0]:fieldmd[0] + fieldmd[1]]
        fields = []
        i = 0
        while i + 8 <= len(fblob):
            rel, kind = struct.unpack_from("<iB", fblob, i)
            if kind == 0 and rel:  # field descriptor
                # struct FieldDescriptor: relativeType(4) relativeName(4)
                # flags(2) kind(2) ...  then superclass(4) then field records
                base = fieldmd[2] + i
                try:
                    fname_rel = struct.unpack_from("<i", fblob, i + 4)[0]
                    fidx = base + 4 + fname_rel - fieldmd[2]
                    if 0 <= fidx < len(fblob):
                        fend = fblob.index(b"\0", fidx)
                        fname = fblob[fidx:fend].decode("utf-8", "replace")
                        fields.append(fname)
                except Exception:
                    pass
            i += 1
        if fields:
            print("\n### field names (%d unique):" % len(set(fields)))
            for f in sorted(set(fields)):
                print(f)


if __name__ == "__main__":
    main()
