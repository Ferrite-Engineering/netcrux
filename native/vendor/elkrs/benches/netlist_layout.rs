//! Layout time on the real-netlist corpus (`goldens/netlists/`):
//!
//!     cargo bench --bench netlist_layout
//!
//! One benchmark per case, the whole `layout_json` call (parse, layout,
//! export), which is what an embedding application pays per scope.

use criterion::{Criterion, criterion_group, criterion_main};

#[path = "../tests/support/netlist.rs"]
mod netlist;

fn netlist_layout(c: &mut Criterion) {
    let Some(dir) = netlist::corpus_dir() else {
        eprintln!("goldens/ not present, nothing to benchmark");
        return;
    };
    let elk = elkrs::create_elk();
    let mut group = c.benchmark_group("netlist_layout");
    // The large scopes take seconds per iteration; ten samples keep a full
    // run to a few minutes.
    group.sample_size(10);
    for (name, input) in netlist::cases(&dir) {
        group.bench_function(&name, |b| {
            b.iter(|| elk.layout_json(std::hint::black_box(&input)).unwrap())
        });
    }
    group.finish();
}

criterion_group!(benches, netlist_layout);
criterion_main!(benches);
