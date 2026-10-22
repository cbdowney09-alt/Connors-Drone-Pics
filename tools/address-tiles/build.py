"""
Build KnoxCanvas address tiles from Overture Maps addresses (National Address Database and
other official sources). The iPhone app reads them for the route optimizer and the street
sweep instead of relying on the public Overpass servers.

Usage (needs `pip install duckdb`):
    python build.py --state TN --bbox -90.32,34.97,-81.64,36.69 --out ../../docs/addr/v1
    python build.py --state TN --parquet tn_addresses.parquet --out ../../docs/addr/v1   # from a local extract

Several states can share one output folder: run once per state; index.json is merged.

Tile layout (served by Vercel from docs/, so at https://connorsdronepics.com/addr/v1/...):
    index.json                 {"v", "source", "tileDeg", "areas": [...], "tiles": ["ty/tx", ...]}
    {ty}/{tx}.json             ty = floor(lat / tileDeg), tx = floor(lng / tileDeg)
        {"v": 1, "st": "TN", "lat0", "lng0",
         "s": [street names], "c": ["City 37909", ...], "cs": [state per city, when a tile spans states],
         "a": [[dLat, dLng, "number", streetIdx, cityIdx], ...]}   dLat/dLng in 1e-5 degrees from lat0/lng0
Tiles on a state line hold both states' houses: building the second state merges into the file
the first one wrote, and "cs" records each city's state ("st" is the first state, for older apps).
Units in one building are merged into one entry per house number + street.
"""
import argparse, json, os, re
from datetime import date

import duckdb

RELEASE = "2026-09-23.1"
TILE_DEG = 0.05
KEEP_UPPER = {"N", "S", "E", "W", "NE", "NW", "SE", "SW", "US", "SR", "TN", "CR", "I"}


def nice(name):
    """'MANDERLY Way' -> 'Manderly Way', '1ST AVE NW' -> '1st Ave NW'."""
    if not name:
        return ""
    out = []
    for w in name.split():
        if w.isupper() and w not in KEEP_UPPER:
            w = w[:1] + w[1:].lower()
        out.append(w)
    return " ".join(out)


def merge(old, new, state):
    """Combine another state's houses into an existing tile (same lat0/lng0)."""
    old_states = old.get("cs") or [old["st"]] * len(old["c"])
    # Drop this state's houses from a previous run, then add the fresh ones.
    keep = [row for row in old["a"] if old_states[row[4]] != state]
    streets, cities, states, rows = {}, {}, [], []
    def add(row, s_name, c_name, st):
        si = streets.setdefault(s_name, len(streets))
        if (c_name, st) not in cities:
            cities[(c_name, st)] = len(cities)
            states.append(st)
        rows.append([row[0], row[1], row[2], si, cities[(c_name, st)]])
    for row in keep:
        add(row, old["s"][row[3]], old["c"][row[4]], old_states[row[4]])
    for row in new["a"]:
        add(row, new["s"][row[3]], new["c"][row[4]], state)
    first = old["st"] if keep else state
    out = {"v": 1, "st": first, "lat0": old["lat0"], "lng0": old["lng0"],
           "s": list(streets), "c": [c for c, _ in cities], "a": rows}
    if len(set(states)) > 1:
        out["cs"] = states
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--bbox", help="minLng,minLat,maxLng,maxLat (for reading from Overture)")
    ap.add_argument("--parquet", help="local extract with lat,lng,number,street,postcode,postal_city,city")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    con = duckdb.connect()
    if a.parquet:
        src = f"read_parquet('{a.parquet}')"
    else:
        x0, y0, x1, y1 = map(float, a.bbox.split(","))
        con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
        s3 = f"s3://overturemaps-us-west-2/release/{RELEASE}/theme=addresses/type=address/*"
        src = f"""(SELECT bbox.ymin AS lat, bbox.xmin AS lng, number, street, postcode, postal_city,
                         address_levels[2].value AS city
                  FROM read_parquet('{s3}', hive_partitioning=1)
                  WHERE bbox.xmin BETWEEN {x0} AND {x1} AND bbox.ymin BETWEEN {y0} AND {y1}
                    AND country = 'US' AND address_levels[1].value = '{a.state}')"""

    rows = con.execute(f"""
        SELECT floor(lat / {TILE_DEG})::INT AS ty, floor(lng / {TILE_DEG})::INT AS tx,
               number, street, coalesce(nullif(postal_city, ''), city, '') AS city, coalesce(postcode, '') AS zip,
               avg(lat) AS lat, avg(lng) AS lng
        FROM {src}
        WHERE number IS NOT NULL AND number <> '' AND street IS NOT NULL AND street <> ''
        GROUP BY ALL
        ORDER BY ty, tx, street, number
    """).fetchall()

    os.makedirs(a.out, exist_ok=True)
    tiles, cur, buf = [], None, None
    total = 0

    def flush():
        nonlocal total
        if not cur:
            return
        ty, tx = cur
        lat0, lng0 = round(ty * TILE_DEG, 5), round(tx * TILE_DEG, 5)
        streets, cities, out = {}, {}, []
        for number, street, city, zip_, lat, lng in buf:
            s = nice(street)
            c = (nice(city) + " " + zip_[:5]).strip()
            si = streets.setdefault(s, len(streets))
            ci = cities.setdefault(c, len(cities))
            out.append([round((lat - lat0) * 1e5), round((lng - lng0) * 1e5), str(number), si, ci])
        d = os.path.join(a.out, str(ty))
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f"{tx}.json")
        tile = {"v": 1, "st": a.state, "lat0": lat0, "lng0": lng0,
                "s": list(streets), "c": list(cities), "a": out}
        if os.path.exists(path):
            with open(path) as f:
                old = json.load(f)
            tile = merge(old, tile, a.state)
        with open(path, "w") as f:
            json.dump(tile, f, separators=(",", ":"))
        tiles.append(f"{ty}/{tx}")
        total += len(out)

    for ty, tx, number, street, city, zip_, lat, lng in rows:
        if (ty, tx) != cur:
            flush()
            cur, buf = (ty, tx), []
        buf.append((number, street, city, zip_, lat, lng))
    flush()

    # Merge with any other states already in this folder.
    idx_path = os.path.join(a.out, "index.json")
    idx = {"v": 1, "tileDeg": TILE_DEG, "areas": [], "tiles": []}
    if os.path.exists(idx_path):
        with open(idx_path) as f:
            idx = json.load(f)
    idx["areas"] = [x for x in idx["areas"] if x["name"] != a.state] + [{"name": a.state, "addresses": total, "tiles": len(tiles)}]
    idx["tiles"] = sorted(set(idx["tiles"]) | set(tiles))
    idx["source"] = f"Overture Maps Foundation addresses, release {RELEASE} (National Address Database and other official sources)"
    idx["built"] = date.today().isoformat()
    with open(idx_path, "w") as f:
        json.dump(idx, f, separators=(",", ":"))
    print(f"{a.state}: {total} houses in {len(tiles)} tiles -> {a.out}")


if __name__ == "__main__":
    main()
