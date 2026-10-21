//! Shared by `tests/netlist_corpus.rs` and `benches/netlist_layout.rs`: the
//! real-netlist corpus under `goldens/netlists/` and the geometry its
//! expectations are written in (see `tools/netlist_geometry.py`).

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::io::Read;
use std::path::{Path, PathBuf};

use serde_json::Value;

/// `goldens/netlists/`, or `None` when the crate's development assets are
/// absent (a packaged build).
pub fn corpus_dir() -> Option<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    if !root.join("goldens").is_dir() {
        return None;
    }
    Some(root.join("goldens/netlists"))
}

/// Every case in the corpus as `(name, ELK JSON input)`, sorted by name.
/// Panics when the corpus directory is missing or empty: inside a checkout
/// that has `goldens/`, an absent corpus is a broken checkout, not a skip.
pub fn cases(dir: &Path) -> Vec<(String, String)> {
    let cases_dir = dir.join("cases");
    let mut paths: Vec<PathBuf> = std::fs::read_dir(&cases_dir)
        .unwrap_or_else(|e| panic!("{}: {e}", cases_dir.display()))
        .map(|e| e.unwrap().path())
        .filter(|p| p.to_string_lossy().ends_with(".json.gz"))
        .collect();
    paths.sort();
    assert!(!paths.is_empty(), "{}: no cases", cases_dir.display());
    paths
        .into_iter()
        .map(|p| {
            let file = p.file_name().unwrap().to_string_lossy();
            let name = file.trim_end_matches(".json.gz").to_owned();
            (name, read_gz(&p))
        })
        .collect()
}

pub fn read_gz(path: &Path) -> String {
    let bytes = std::fs::read(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    let mut text = String::new();
    flate2::read::GzDecoder::new(&bytes[..])
        .read_to_string(&mut text)
        .unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    text
}

fn num(v: &Value, key: &str) -> f64 {
    v.get(key).and_then(Value::as_f64).unwrap_or(0.0)
}

fn bx(v: &Value) -> Vec<f64> {
    vec![num(v, "x"), num(v, "y"), num(v, "width"), num(v, "height")]
}

fn pt(v: &Value, out: &mut Vec<f64>) {
    out.push(num(v, "x"));
    out.push(num(v, "y"));
}

fn arr(v: &Value, key: &str) -> Vec<Value> {
    v.get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn id(v: &Value) -> String {
    v["id"].as_str().expect("element id").to_owned()
}

/// The geometry of a laid-out flat graph, keyed as
/// `tools/netlist_geometry.py` keys it.
pub fn geometry(layout: &Value) -> BTreeMap<String, Vec<f64>> {
    let mut g = BTreeMap::new();
    g.insert("root".to_owned(), bx(layout));
    for n in arr(layout, "children") {
        let nid = id(&n);
        assert!(
            arr(&n, "children").is_empty() && arr(&n, "edges").is_empty(),
            "{nid}: nested graphs are not part of this corpus"
        );
        g.insert(format!("node:{nid}"), bx(&n));
        for (i, label) in arr(&n, "labels").iter().enumerate() {
            g.insert(format!("label:{nid}#{i}"), bx(label));
        }
        for p in arr(&n, "ports") {
            let pid = id(&p);
            g.insert(format!("port:{pid}"), bx(&p));
            for (i, label) in arr(&p, "labels").iter().enumerate() {
                g.insert(format!("label:{pid}#{i}"), bx(label));
            }
        }
    }
    for e in arr(layout, "edges") {
        let eid = id(&e);
        let mut points = Vec::new();
        for s in arr(&e, "sections") {
            pt(&s["startPoint"], &mut points);
            for b in arr(&s, "bendPoints") {
                pt(&b, &mut points);
            }
            pt(&s["endPoint"], &mut points);
        }
        g.insert(format!("edge:{eid}"), points);
        let junctions = arr(&e, "junctionPoints");
        if !junctions.is_empty() {
            let mut points = Vec::new();
            for j in &junctions {
                pt(j, &mut points);
            }
            g.insert(format!("junctions:{eid}"), points);
        }
    }
    g
}

/// The stored expectation for case `name`.
pub fn expected(dir: &Path, name: &str) -> BTreeMap<String, Vec<f64>> {
    let path = dir.join(format!("expected/{name}.geometry.json.gz"));
    serde_json::from_str(&read_gz(&path)).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}
