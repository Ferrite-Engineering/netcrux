# Malformed Yosys-JSON corpus

Hand-authored adversarial inputs, one file per malformed-input invariant.
Consumed by `test/services/yosys/yosys_json_fuzz_test.dart`, which asserts
every case yields a typed `YosysJsonParseException` (never a raw
`FormatException` / `TypeError`, never a hang, never a partial netlist).

The invariants the corpus pins:

1. A non-object root is rejected.
2. A document with no `modules` key is rejected.
3. A nested member of the wrong type is rejected, naming its module.
4. An empty object is a failure, not an empty netlist.
5. A document cut short — mid-token or inside a string — is rejected.
6. Nesting depth is bounded.

| File | Invariant |
|------|-----------|
| `non_object_root_array.json` | #1 non-object root (`[]`) |
| `non_object_root_scalar.json` | #1 non-object root (`42`) |
| `missing_modules.json` | #2 missing `modules` key |
| `empty_object.json` | #4 empty `{}` (failure, not an empty netlist) |
| `nested_type_error.json` | #3 a cell's `connections` is a string |
| `truncated.json` | #5 cut mid-token |
| `unterminated_module_name.json` | #5 unterminated string |

The fuzz test adds programmatic cases on top of this corpus: seeded random
truncation of a valid netlist, random type-mutation, and a deeply-nested
array (#6).

Every input has an `.expected_error.json` companion naming the exception it
must raise and the invariant it exercises; the static fixture guards under
`test/static/` refuse an input without one.
