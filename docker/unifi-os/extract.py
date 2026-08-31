#!/usr/bin/env python3
import mmap
import struct
import sys
import zlib
from pathlib import Path


class FirmwareError(Exception):
    pass


def squashfs_bytes_used(superblock: bytes, remaining: int) -> int:
    if superblock[:4] != b"hsqs":
        raise FirmwareError("PARTrootfs payload is not squashfs")
    used = struct.unpack_from("<Q", superblock, 40)[0]
    if used < 96 or used > remaining:
        raise FirmwareError(f"invalid squashfs bytes_used {used}")
    return used


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def extract(fwfile: Path, savedir: Path) -> None:
    savedir.mkdir(parents=True, exist_ok=True)
    with fwfile.open("rb") as handle:
        mapping = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            if mapping[0:4] != b"UBNT":
                raise FirmwareError(f"{fwfile} is not a UBNT firmware image")
            header = mapping[0:0x104]
            header_crc = int.from_bytes(mapping[0x104:0x108], "big")
            if crc32(header) != header_crc:
                raise FirmwareError(f"{fwfile} header CRC mismatch")
            version = header[4:].split(b"\x00", 1)[0].decode("utf-8", "replace")
            _ = (savedir / "version").write_text(version + "\n")
            print(version)

            offset = 0x108
            while offset + 4 <= len(mapping):
                tag = bytes(mapping[offset : offset + 4])
                if tag == b"\x00\x00\x00\x00":
                    offset += 4
                    continue
                if tag != b"FILE":
                    break
                if offset + 0x38 > len(mapping):
                    raise FirmwareError("truncated FILE header")
                file_header = bytes(mapping[offset : offset + 0x38])
                name = file_header[4:33].split(b"\x00", 1)[0].decode("utf-8", "replace")
                position = file_header[39]
                length = int.from_bytes(file_header[48:52], "big")
                start = offset + 0x38
                end = start + length
                if end + 8 > len(mapping):
                    raise FirmwareError(f"truncated FILE {name}")
                payload = bytes(mapping[start:end])
                footer_crc = int.from_bytes(mapping[end : end + 4], "big")
                if crc32(file_header + payload) != footer_crc:
                    raise FirmwareError(f"CRC mismatch for FILE {name}")
                _ = (savedir / f"{name}.bin").write_bytes(payload)
                print(f"FILE {position} {name} {length}")
                offset = end + 8

            part = mapping.find(b"PARTrootfs", offset if offset < len(mapping) else 0)
            if part < 0:
                part = mapping.find(b"PARTrootfs")
            if part < 0:
                raise FirmwareError("no PARTrootfs found")
            payload_off = part + 0x38
            remaining = len(mapping) - payload_off
            superblock = mapping[payload_off : payload_off + 96]
            used = squashfs_bytes_used(superblock, remaining)
            _ = (savedir / "rootfs.squashfs").write_bytes(
                mapping[payload_off : payload_off + used]
            )
            print(f"PART rootfs squashfs {used}")
        finally:
            mapping.close()


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: extract.py <firmware> <outdir>", file=sys.stderr)
        sys.exit(1)
    try:
        extract(Path(sys.argv[1]), Path(sys.argv[2]))
    except FirmwareError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
