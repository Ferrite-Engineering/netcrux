// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

//! Reads the vendored elkrs crate's version out of its manifest so the
//! library can report it without a second copy of the number.

use std::fs;

fn main() {
    let manifest = fs::read_to_string("../vendor/elkrs/Cargo.toml")
        .expect("native/vendor/elkrs/Cargo.toml is readable");
    let version = manifest
        .lines()
        .find_map(|line| {
            line.strip_prefix("version = \"")
                .and_then(|rest| rest.strip_suffix('"'))
        })
        .expect("elkrs manifest has a version line");
    println!("cargo:rustc-env=ELK_FFI_ELKRS_VERSION={version}");
    println!("cargo:rerun-if-changed=../vendor/elkrs/Cargo.toml");
}
