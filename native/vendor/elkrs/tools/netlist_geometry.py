#!/usr/bin/env python3
"""Extracts the geometry of a laid-out ELK JSON graph, for the netlist corpus.

    python3 tools/netlist_geometry.py <layout.json> <out.geometry.json.gz>

The output is one JSON object keyed by element, each value a flat list of
numbers: what a schematic draws, and nothing an exporter is free to spell
differently (option echoes, section ids, number formatting).

    root                [x, y, width, height]
    node:<id>           [x, y, width, height]
    port:<id>           [x, y, width, height]   (relative to its node)
    label:<owner>#<i>   [x, y, width, height]
    edge:<id>           [x0, y0, x1, y1, ...]   (each section: start, bends, end)
    junctions:<id>      [x0, y0, ...]           (only when the edge has any)

tests/netlist_corpus.rs extracts the same keys from this crate's output and
compares them exactly. Keep the two in step.
"""
import gzip
import json
import sys


def box(o):
    return [float(o.get("x", 0)), float(o.get("y", 0)), float(o["width"]), float(o["height"])]


def pt(p):
    return [float(p["x"]), float(p["y"])]


def geometry(d):
    g = {"root": box(d)}
    for n in d.get("children", []):
        nid = n["id"]
        if n.get("children") or n.get("edges"):
            raise SystemExit(f"{nid}: nested graphs are not part of this corpus")
        g["node:" + nid] = box(n)
        for i, lab in enumerate(n.get("labels", [])):
            g[f"label:{nid}#{i}"] = box(lab)
        for p in n.get("ports", []):
            g["port:" + p["id"]] = box(p)
            for i, lab in enumerate(p.get("labels", [])):
                g[f"label:{p['id']}#{i}"] = box(lab)
    for e in d.get("edges", []):
        pts = []
        for s in e.get("sections", []):
            pts += pt(s["startPoint"])
            for b in s.get("bendPoints", []):
                pts += pt(b)
            pts += pt(s["endPoint"])
        g["edge:" + e["id"]] = pts
        if e.get("junctionPoints"):
            jp = []
            for p in e["junctionPoints"]:
                jp += pt(p)
            g["junctions:" + e["id"]] = jp
    return dict(sorted(g.items()))


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    with open(argv[1]) as f:
        g = geometry(json.load(f))
    data = (json.dumps(g, separators=(",", ":")) + "\n").encode()
    with open(argv[2], "wb") as f:
        f.write(gzip.compress(data, compresslevel=9, mtime=0))
    print(f"{argv[2]}: {len(g)} elements")


if __name__ == "__main__":
    main(sys.argv)
