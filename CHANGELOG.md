# Changelog

## Unreleased

- Add optional `decoder_sources` metadata for RustQ-authored skip helpers.
- Emit Rustler macro prelude helpers only for requested generator features.
- Add opt-in descriptor-backed sparse message generation with
  `sparse_messages: :descriptor`.
- Move sparse primitive value helpers, descriptor scanning, descriptor dispatch,
  and sparse descriptor declarations into RustQ-authored `defrust` / `@type`
  support.
- Author the sparse message descriptor macro with item-generating
  `defrustmacro` and compact `repeat` macro-template support.
- Share descriptor field inventories between sparse and skip message decoders
  when both descriptor sparse and skip features are generated.
- Compact primitive aliases inside descriptor macro invocations to reduce
  generated Rust source size.
- Move descriptor-backed skip message scanning into RustQ-authored `defrust`
  helpers with sorted field lookup.
- Collapse the separate sparse bytes descriptor mode into ordinary `one`
  descriptor mode.

## v0.2.2 - 2026-06-28

- Centralize primitive Rustler decoder metadata.
- Compact generated skip decoders.
- Deduplicate sparse enum decoders when full enum decoders are generated.
- Compact generated enum decoders.
- Remove the unused Rustler decoder macro path.
- Update RustQ dependency to `~> 0.8.2`.

## v0.2.1 - 2026-06-26

- Generate Rustler decoders through shared Rust macros to reduce repeated generated source.
- Add generic Rustler sparse and skip decoder families for projection-oriented native backends.

## v0.2.0 - 2026-06-26

- Delegate LEB128/ZigZag integer encoding to the `varint` package while keeping Kiwi-specific range and error handling.
- Replace vague `FieldProps`/`MessageProps` modules with `KiwiCodec.Metadata` and `KiwiCodec.Metadata.Field`.
- Rename the Kiwi variable-length float wire module to `KiwiCodec.Wire.VarFloat`.
- Rename generated module metadata API from `__kiwi_props__/0` to `__kiwi_metadata__/0`.
- Split Rustler generator naming, selection, helper splice, and decoder macro concerns into dedicated modules.
- Rename generated Elixir source rendering from `KiwiCodec.Generator` to `KiwiCodec.ModuleGenerator`.
- Clarify generated-codec and runtime helper names around definitions, wire fields, and wire types.
- Replace caller-owned Rustler templates with `KiwiCodec.RustlerGenerator.source/2` for complete generated Rust source.
- Centralize Kiwi primitive type metadata in `KiwiCodec.PrimitiveType`.
- Rename schema runtime interpretation to `KiwiCodec.SchemaInterpreter`.
- Split vague `KiwiCodec.Compiler` responsibilities into `KiwiCodec.ModuleCompiler` and `KiwiCodec.FileGenerator`.
- Split parsed schema members into `KiwiCodec.Schema.Field` with `id` and `KiwiCodec.Schema.EnumVariant` with `value`.
- Replace overloaded parsed schema definitions with `KiwiCodec.Schema.Enum`, `KiwiCodec.Schema.Struct`, and `KiwiCodec.Schema.Message`.
- Extract compact binary schema type-reference encoding into `KiwiCodec.Schema.Binary.TypeIndex`.
- Split Rustler generator definition emission, field expressions, and entrypoints into dedicated modules.
- Split generated-module metadata, shape, and typespec emission out of `KiwiCodec.DSL`.
- Split schema tokenization and validation out of `KiwiCodec.Schema.Parser`.
- Group published HexDocs modules without hiding source documentation.
- Refresh README installation instructions for the latest released version.
- Infer Rustler generator entrypoint names and selected definitions from requested schema definitions.
- Render Rustler generator source prelude with RustQ AST imports instead of raw Rust strings.
- Infer Rustler generator entrypoints from matching exported NIF stub modules.
- Infer Rustler generator entrypoints from explicit NIF stub metadata modules without loading Rustler modules.
- Document inferred Rustler entrypoints and NIF stub metadata usage.

## v0.1.1 - 2026-06-25

- Reject unexpected characters while parsing `.kiwi` schema text.
- Normalize malformed binary schema failures to `KiwiCodec.DecodeError`.
- Document internal modules and Rustler generator template requirements.
- Reuse RustQ Rustler helper splices for generated native struct term construction.

## v0.1.0 - 2026-06-25

- Initial Kiwi wire codec, schema parser, runtime interpreter, DSL, and code generator.
