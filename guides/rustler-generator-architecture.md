# Rustler generator architecture

KiwiCodec's Rustler generator is optimized for two goals at the same time:

1. Keep generator code semantic and maintainable in Elixir.
2. Keep generated Rust source compact enough for large downstream schemas.

For repetitive schema decoders, those goals are served by a compact macro
boundary rather than by fully expanding every decoder body.

## Layers

The generator is organized as a small pipeline:

1. Schema definitions are parsed and selected by `KiwiCodec.RustlerGenerator`.
2. Definition-specific modules (`Definition`, `Sparse`, and `Skip`) derive
   semantic field metadata and field expressions from the schema.
3. `KiwiCodec.RustlerGenerator.DecoderMacro` lowers that metadata to compact
   Rust macro invocations such as `kiwi_message_decoder!`,
   `kiwi_sparse_message_decoder!`, and `kiwi_skip_message_decoder!`.
4. `KiwiCodec.RustlerGenerator.Splice` provides the shared Rust macro
   definitions and helper functions consumed by those invocations.
5. `KiwiCodec.RustlerGenerator.Entrypoint` emits Rustler NIF entrypoints through
   RustQ `defrust`, where the wrapper control flow is small and readable.

This split keeps schema logic in Elixir while avoiding thousands of repeated
expanded Rust function bodies.

## Compact macro boundary

The macros in `Splice` are an intentional escape boundary. They are not a
string DSL to grow casually; they are shared Rust implementations for highly
repetitive decoder shapes.

When changing full, sparse, or skip decoder generation:

- Prefer semantic Elixir metadata and helpers first.
- Keep compact schema-specific output as macro invocations when the expanded
  body would be repetitive.
- Use RustQ AST for local expression/arm/function generation where it remains
  compact, such as skip field arms used by downstream custom templates.
- Do not replace compact decoder macro invocations with fully expanded Rust just
  to say the generator is "AST-backed" or "defrust-backed".

A good change should make the Elixir generator clearer without increasing large
schema output size.

## Dogfooding size guardrail

Figler is the main downstream stress test for generated Rust size. It should be
used as a private dogfood check, not updated or published automatically.

As of the current generator polish, Figler with local KiwiCodec should generate
approximately:

- `29,383` lines
- `1,070,917` bytes

Small formatting or schema changes can move this slightly, but a large jump
usually means a compact macro boundary was accidentally expanded.

## Practical checklist

Before committing Rustler generator changes:

1. Capture a generated Rust baseline for a schema that exercises full, sparse,
   and skip decoders.
2. Make the smallest semantic change.
3. Confirm generated output is unchanged or intentionally smaller.
4. Run KiwiCodec `mix ci` and warning-free docs.
5. Dogfood Figler with a temporary local KiwiCodec dependency.
6. Restore Figler before committing KiwiCodec changes unless a Figler update was
   explicitly requested.
