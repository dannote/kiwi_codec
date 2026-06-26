# KiwiCodec

Elixir implementation of the Kiwi schema/binary codec.

## Development

```sh
mix deps.get
mix ci
```

## Scope

- Keep `KiwiCodec` generic: schema parser/runtime interpreter, DSL/codegen, wire primitives, and generic containers.
- Product-specific schemas belong in companion packages.
- Prefer generated Elixir modules for application code; use `KiwiCodec.SchemaInterpreter` only when schemas are loaded at runtime.
- Preserve binary compatibility with the OpenPencil TypeScript runtime in `../open-pencil-app/packages/core/src/kiwi/schema-runtime`.
