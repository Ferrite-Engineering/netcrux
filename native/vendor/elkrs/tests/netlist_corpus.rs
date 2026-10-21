//! Real-netlist corpus: every case in `goldens/netlists/cases/` must lay out
//! to exactly the geometry elkjs (the GWT build of the Java ELK) produced
//! for it, stored in `goldens/netlists/expected/`. The inputs are schematic
//! scopes of two open RISC-V cores with a schematic viewer's option set;
//! `goldens/netlists/PROVENANCE.md` says where each came from.

#![cfg(not(target_arch = "wasm32"))]

#[path = "support/netlist.rs"]
mod netlist;

#[test]
fn netlist_corpus_matches_elkjs() {
    let Some(dir) = netlist::corpus_dir() else {
        eprintln!("goldens/ not present, skipping the netlist corpus");
        return;
    };
    let elk = elkrs::create_elk();
    let mut failures = Vec::new();
    let cases = netlist::cases(&dir);
    for (name, input) in &cases {
        let expected = netlist::expected(&dir, name);
        let layout = match elk.layout_json(input) {
            Ok(layout) => layout,
            Err(e) => {
                failures.push(format!("{name}: layout error: {e}"));
                continue;
            }
        };
        let actual = netlist::geometry(&layout);
        let mut diffs = Vec::new();
        for (key, want) in &expected {
            match actual.get(key) {
                None => diffs.push(format!("{key}: missing")),
                Some(got) if got != want => diffs.push(format!("{key}: {got:?} != {want:?}")),
                Some(_) => {}
            }
        }
        for key in actual.keys() {
            if !expected.contains_key(key) {
                diffs.push(format!("{key}: not in the expectation"));
            }
        }
        if !diffs.is_empty() {
            failures.push(format!(
                "{name}: {} of {} elements differ\n  {}",
                diffs.len(),
                expected.len(),
                diffs[..diffs.len().min(10)].join("\n  ")
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} netlist cases failed:\n{}",
        failures.len(),
        cases.len(),
        failures.join("\n")
    );
    println!("all {} netlist cases identical to elkjs", cases.len());
}
