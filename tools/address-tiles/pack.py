"""
Pack a folder of address tiles (from build.py) into one file the iPhone app ships with.

Usage:
    python pack.py --tiles ../../docs/addr/v1 --states TN --out ../../ios-native/KnoxCanvas/Resources/addresses.knxa

Format (little-endian):
    "KNXA" | u32 version=1 | u32 tileCount | u32 metaLength | meta JSON (utf-8)
    tileCount x (i32 ty, i32 tx, u64 offset, u32 length)     offsets from the start of the file
    tile blobs: raw DEFLATE (no zlib header) of each tile's JSON, which is what Apple's
    NSData.decompressed(using: .zlib) reads.
Only tiles whose "st" is in --states are packed.
"""
import argparse, json, os, struct, zlib


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", required=True)
    ap.add_argument("--states", required=True, help="comma-separated, e.g. TN,KY")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    states = set(a.states.split(","))

    with open(os.path.join(a.tiles, "index.json")) as f:
        idx = json.load(f)
    blobs = []
    for key in idx["tiles"]:
        ty, tx = map(int, key.split("/"))
        with open(os.path.join(a.tiles, str(ty), f"{tx}.json"), "rb") as f:
            raw = f.read()
        if json.loads(raw).get("st") not in states:
            continue
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        blobs.append((ty, tx, c.compress(raw) + c.flush()))

    meta = json.dumps({"tileDeg": idx["tileDeg"], "states": sorted(states), "source": idx.get("source", ""),
                       "built": idx.get("built", "")}).encode()
    head = 16 + len(meta)
    table = 20 * len(blobs)
    offset = head + table
    with open(a.out, "wb") as f:
        f.write(b"KNXA" + struct.pack("<III", 1, len(blobs), len(meta)) + meta)
        for ty, tx, b in blobs:
            f.write(struct.pack("<iiQI", ty, tx, offset, len(b)))
            offset += len(b)
        for _, _, b in blobs:
            f.write(b)
    print(f"{len(blobs)} tiles, {os.path.getsize(a.out) / 1e6:.1f} MB -> {a.out}")


if __name__ == "__main__":
    main()
