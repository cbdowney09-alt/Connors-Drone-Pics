"""
Build one downloadable pack per state (XX.knxa) plus manifest.json for the iPhone app's
Account → House data screen, from a national Overture extract partitioned by state.

    # 1. Extract (about 10-20 minutes, ~2 GB): every US address, one folder per state
    #    (see extract_us.py)
    # 2. Build packs:
    python build_all.py --extract /path/to/us --out /path/to/packs --jobs 4
    # 3. Publish them as a GitHub release (tools/address-tiles/publish.sh)

Each state gets its own tiles (a tile on a state line appears in both states' packs, each with
its own houses); the app reads every installed pack and combines them.
"""
import argparse, glob, json, os, shutil, subprocess, sys
from concurrent.futures import ProcessPoolExecutor
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build import RELEASE  # noqa: E402

NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
    "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
    "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
    "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
}


def one(args):
    st, extract, out, work = args
    tiles = os.path.join(work, st)
    shutil.rmtree(tiles, ignore_errors=True)
    py = sys.executable
    parquet = os.path.join(extract, f"st={st}", "*.parquet")
    subprocess.run([py, os.path.join(HERE, "build.py"), "--state", st, "--parquet", parquet, "--out", tiles],
                   check=True, stdout=subprocess.DEVNULL)
    pack = os.path.join(out, f"{st}.knxa")
    subprocess.run([py, os.path.join(HERE, "pack.py"), "--tiles", tiles, "--states", st, "--out", pack],
                   check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(tiles, "index.json")) as f:
        houses = json.load(f)["areas"][0]["addresses"]
    shutil.rmtree(tiles, ignore_errors=True)
    print(f"{st}: {houses:,} houses, {os.path.getsize(pack) / 1e6:.1f} MB", flush=True)
    return {"code": st, "name": NAMES[st], "bytes": os.path.getsize(pack), "houses": houses, "version": RELEASE}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extract", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--only", help="comma-separated states (default: all in the extract)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    work = os.path.join(a.out, "_work")
    states = sorted(os.path.basename(p)[3:] for p in glob.glob(os.path.join(a.extract, "st=*")))
    states = [s for s in states if s in NAMES and (not a.only or s in a.only.split(","))]
    with ProcessPoolExecutor(a.jobs) as ex:
        infos = list(ex.map(one, [(s, a.extract, a.out, work) for s in states]))
    shutil.rmtree(work, ignore_errors=True)

    # Merge with any states already built into this folder.
    path = os.path.join(a.out, "manifest.json")
    old = {}
    if os.path.exists(path):
        with open(path) as f:
            old = {s["code"]: s for s in json.load(f)["states"]}
    old.update({i["code"]: i for i in infos})
    manifest = {"version": RELEASE, "built": date.today().isoformat(),
                "source": f"Overture Maps Foundation addresses, release {RELEASE} (National Address Database and other official sources)",
                "states": sorted(old.values(), key=lambda s: s["name"])}
    with open(path, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(s["bytes"] for s in manifest["states"])
    print(f"{len(manifest['states'])} states, {total / 1e9:.2f} GB -> {a.out}")


if __name__ == "__main__":
    main()
