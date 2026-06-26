# Changelog

## Unreleased

- Delegate LEB128/ZigZag integer encoding to the `varint` package while keeping Kiwi-specific range and error handling.
- Replace vague `FieldProps`/`MessageProps` modules with `KiwiCodec.Metadata` and `KiwiCodec.Metadata.Field`.
- Rename the Kiwi variable-length float wire module to `KiwiCodec.Wire.VarFloat`.
- Rename generated module metadata API from `__kiwi_props__/0` to `__kiwi_metadata__/0`.
- Split Rustler generator naming, selection, helper splice, and decoder macro concerns into dedicated modules.
- Rename generated Elixir source rendering from `KiwiCodec.Generator` to `KiwiCodec.ModuleGenerator`.
- Clarify generated-codec and runtime helper names around definitions, wire fields, and wire types.
- Replace caller-owned Rustler templates with `KiwiCodec.RustlerGenerator.source/2` for complete generated Rust source.

## v0.1.1 - 2026-06-25

- Reject unexpected characters while parsing `.kiwi` schema text.
- Normalize malformed binary schema failures to `KiwiCodec.DecodeError`.
- Document internal modules and Rustler generator template requirements.
- Reuse RustQ Rustler helper splices for generated native struct term construction.

## v0.1.0 - 2026-06-25

- Initial Kiwi wire codec, schema parser, runtime interpreter, DSL, and code generator.
