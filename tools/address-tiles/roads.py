"""
Build KnoxCanvas road tiles from the U.S. Census TIGER/Line road files (public domain). The
website uses them to fill GPS gaps: when a canvasser's screen was off, it finds the walking
route along real streets between the last and next GPS dots, then offers the houses along it
for the canvasser to confirm ("Is this the route you walked?").

Usage (needs `pip install duckdb`; the spatial extension downloads itself):
    # 1. Download one state's county road files, e.g. North Carolina (FIPS 37):
    #    https://www2.census.gov/geo/tiger/TIGER2025/ROADS/tl_2025_37*_roads.zip  →  ./nc/
    python roads.py --zips 'nc/*.zip' --out ../../docs/roads/v1

Several states can share one output folder: run once per state; index.json is merged and tiles
on a state line keep both states' roads.

Tile layout (served by Vercel from docs/, so at https://knoxcanvas.app/roads/v1/...), on the same
0.05° grid as the address tiles:
    index.json           {"v", "tileDeg", "source", "tiles": ["ty/tx", ...]}
    {ty}/{tx}.json       {"v": 1, "lat0", "lng0", "n": [road names],
                          "r": [[id, nameIdx, cls, x0, y0, dx1, dy1, dx2, dy2, ...], ...]}
x/y are 1e-5° steps from lng0/lat0 (the first point), then steps from the previous point. Each road
is cut into one piece per tile; where it crosses into the next tile the crossing segment is in
both pieces, so they share points. Roads meet where they share a point, which is how TIGER stores
intersections. `id` is the same for every piece of one road.
cls: 1 local street, 2 secondary road, 3 service drive, 4 walkway or path, 5 alley,
     6 private road, 7 parking lot road. Interstates, ramps and 4WD trails are left out:
     nobody canvasses them, and leaving them out keeps routes on walkable streets.
"""
import argparse, glob, json, os
from datetime import date

import duckdb

TILE_DEG = 0.05
CLS = {"S1400": 1, "S1200": 2, "S1640": 3, "S1710": 4, "S1720": 4, "S1820": 4, "S1830": 4,
       "S1730": 5, "S1740": 6, "S1780": 7}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zips", required=True, help="glob of tl_YYYY_SSCCC_roads.zip files")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    files = sorted(glob.glob(a.zips))
    if not files:
        raise SystemExit("no files match " + a.zips)
    con = duckdb.connect()
    con.execute("INSTALL spatial; LOAD spatial;")
    parts = []
    for f in files:
        shp = os.path.basename(f).replace(".zip", ".shp")
        parts.append(f"SELECT LINEARID, FULLNAME, MTFCC, geom FROM ST_Read('/vsizip/{os.path.abspath(f)}/{shp}')")
    con.execute("CREATE TABLE r AS " + " UNION ALL ".join(parts))
    # A road can sit in two county files (it runs along the line between them): keep one copy.
    rows = con.execute(f"""
        SELECT FULLNAME, MTFCC, ST_AsText(geom) AS wkt,
               ST_XMin(geom) x0, ST_YMin(geom) y0, ST_XMax(geom) x1, ST_YMax(geom) y1
        FROM (SELECT *, row_number() OVER (PARTITION BY LINEARID, MTFCC, coalesce(FULLNAME, '')) k FROM r)
        WHERE k = 1 AND MTFCC IN ({",".join("'%s'" % c for c in CLS)})
    """).fetchall()

    tiles = {}
    next_id = 0
    idx_path = os.path.join(a.out, "index.json")
    if os.path.exists(idx_path):  # keep ids unique when another state was built into this folder
        with open(idx_path) as f:
            next_id = json.load(f).get("nextId", 0)
    for name, mtfcc, wkt, x0, y0, x1, y1 in rows:
        for pts in parse_lines(wkt):
            if len(pts) < 2:
                continue
            rid = next_id
            next_id += 1
            for key, piece in split_by_tile(pts):
                tiles.setdefault(key, []).append((rid, name or "", CLS[mtfcc], piece))

    os.makedirs(a.out, exist_ok=True)
    written = []
    for (ty, tx), roads in tiles.items():
        path = os.path.join(a.out, str(ty), f"{tx}.json")
        lat0, lng0 = ty * 5000, tx * 5000  # tile origin in 1e-5° steps
        names, out = {}, []
        if os.path.exists(path):  # another state already wrote this tile: keep its roads
            with open(path) as f:
                old = json.load(f)
            for r in old["r"]:
                names.setdefault(old["n"][r[1]], len(names))
                out.append([r[0], names[old["n"][r[1]]]] + r[2:])
        for rid, name, cls, pts in roads:
            ni = names.setdefault(name, len(names))
            row = [rid, ni, cls]
            px, py = lng0, lat0
            for x, y in pts:
                row += [x - px, y - py]
                px, py = x, y
            out.append(row)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump({"v": 1, "lat0": ty * TILE_DEG, "lng0": tx * TILE_DEG, "n": list(names), "r": out},
                      f, separators=(",", ":"))
        written.append(f"{ty}/{tx}")

    idx = {"v": 1, "tileDeg": TILE_DEG, "tiles": [], "nextId": 0}
    if os.path.exists(idx_path):
        with open(idx_path) as f:
            idx = json.load(f)
    idx["tiles"] = sorted(set(idx["tiles"]) | set(written))
    idx["nextId"] = next_id
    idx["source"] = "U.S. Census Bureau TIGER/Line roads (public domain)"
    idx["built"] = date.today().isoformat()
    with open(idx_path, "w") as f:
        json.dump(idx, f, separators=(",", ":"))
    print(f"{len(rows)} roads in {len(written)} tiles -> {a.out}")


def tile_of(x, y):
    step = round(TILE_DEG * 1e5)
    return (y // step, x // step)


def split_by_tile(pts):
    """Cut a road into one piece per tile it passes through. Where it crosses into the next tile,
    the crossing segment goes in both pieces, so they share end points and still connect."""
    pieces, cur, key = [], [pts[0]], tile_of(*pts[0])
    for p in pts[1:]:
        k = tile_of(*p)
        cur.append(p)
        if k != key:
            pieces.append((key, cur))
            cur, key = [cur[-2], p], k
    pieces.append((key, cur))
    return pieces


def parse_lines(wkt):
    """'LINESTRING (x y, ...)' or 'MULTILINESTRING ((...), (...))' → one list of (x, y) per
    line, in whole 1e-5° steps."""
    body = wkt[wkt.index("(") + 1: wkt.rindex(")")]
    out = []
    for part in body.split("),"):
        pts = []
        for p in part.replace("(", "").replace(")", "").split(","):
            if not p.strip():
                continue
            x, y = p.split()[:2]
            q = (round(float(x) * 1e5), round(float(y) * 1e5))
            if not pts or pts[-1] != q:
                pts.append(q)
        out.append(pts)
    return out


if __name__ == "__main__":
    main()
