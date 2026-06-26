# Changelog

## Unreleased

## v0.1.1 - 2026-06-25

- Reject unexpected characters while parsing `.kiwi` schema text.
- Normalize malformed binary schema failures to `KiwiCodec.DecodeError`.
- Document internal modules and Rustler generator template requirements.
- Reuse RustQ Rustler helper splices for generated native struct term construction.

## v0.1.0 - 2026-06-25

- Initial Kiwi wire codec, schema parser, runtime interpreter, DSL, and code generator.
