# NetCrux (Open Core) — Verification Fixtures

Committed test fixtures consumed by `VERIFICATION_GUIDE.md` and the corresponding integration tests.

## Layout convention

```
fixtures/
├── elaboration/         # Hand-crafted Verilog/VHDL source + .expected.json elaborated Yosys JSON
├── layout/              # Fixed-position layout regression inputs/outputs
├── cross_probe/         # CXP manifest fixtures, hierarchical path corner cases
└── helpers/             # Regeneration scripts (also documented under tool/)
```

Each subfolder corresponds to a verification section in `VERIFICATION_GUIDE.md`. Fixtures must come with:

- The source artifact (`.v`, `.vhd`, `.netcrux`, etc.)
- A companion `.expected.*.json` file capturing the canonical result
- The exact regeneration command in `helpers/README.md` and the corresponding script in `../../tool/`

## Adding a new fixture

1. Create the subfolder if it does not exist
2. Commit the artifact + the `.expected.*.json` companion in the same commit as the feature it verifies
3. Add or update the regenerator script under `../../tool/` and document the command in `helpers/README.md`
4. Reference the fixture from the matching `VERIFICATION_GUIDE.md` section
5. Add the corresponding bullet to `VERIFICATION_CHECKLIST.md`

A shipped feature whose fixtures are missing is a code-review-blocking defect — same rule as WaveCrux.
