# KiwiCodec

KiwiCodec is a pure Elixir implementation of the Kiwi schema binary codec: a compact, schema-driven message format similar in spirit to Protocol Buffers but with its own wire encoding.

The package stays generic: product-specific `.kiwi` schemas can live in companion packages.

## Scope

KiwiCodec owns:

- Kiwi wire primitives: varuint, zigzag int, uint64/int64, varfloat, null-terminated strings, and length-prefixed byte arrays
- `.kiwi` schema parsing and validation
- Schema interpretation for parsed schemas
- Field metadata, including original schema field names
- An idiomatic Elixir DSL and code generator for static modules
- Generic chunk container helpers

## Static modules

Generated modules are regular Elixir structs:

```elixir
defmodule Example.Node do
  use KiwiCodec, kind: :message

  field :id, 1, type: :uint
  field :name, 2, type: :string
end

node = %Example.Node{id: 42, name: "hello"}
binary = KiwiCodec.encode(node)
node = KiwiCodec.decode(binary, Example.Node)
```

Enums use atoms:

```elixir
defmodule Example.Kind do
  use KiwiCodec, kind: :enum

  enum_value :none, 0
  enum_value :frame, 4
end
```

## Schema compilation

For application code, compile schema text into Elixir modules and use the static struct API:

```sh
mix kiwi.gen schema.kiwi --module-prefix MyApp.Schema --out lib/generated
```

For tests and tooling, modules can also be compiled in memory:

```elixir
KiwiCodec.compile_schema!(schema_text, module_prefix: MyApp.Schema)
```

`KiwiCodec.parse_schema!/1` only parses schema text into an AST. It does not create modules by itself.

## Schema interpretation

When a schema is loaded at runtime and you do not want to generate modules, use `KiwiCodec.SchemaInterpreter`:

```elixir
schema = KiwiCodec.parse_schema!(schema_text)
binary = KiwiCodec.SchemaInterpreter.encode(schema, "Thing", %{"id" => 1, "name" => "demo"})
value = KiwiCodec.SchemaInterpreter.decode(schema, "Thing", binary)
```

## Transform modules

Modules can override `transform_module/0` for custom normalization before encode and after decode:

```elixir
defmodule Example.Transform do
  @behaviour KiwiCodec.TransformModule

  def encode(message, _module), do: message
  def decode(message, _module), do: message
end
```

## Binary schemas

```elixir
binary_schema = KiwiCodec.Schema.Binary.encode(schema)
schema = KiwiCodec.Schema.Binary.decode(binary_schema)
```

## Rustler decoder generation

`KiwiCodec.RustlerGenerator.source/2` returns complete generated Rust source for
native Rustler decoders. Use it from `rustq.exs` and let `mix rustq.gen` own
writing and freshness checks:

```elixir
use RustQ.Config

schema = KiwiCodec.parse_schema!(File.read!("priv/schema.kiwi"))

generate :native_decoders, "native/my_nif/src/generated.rs" do
  content KiwiCodec.RustlerGenerator.source(schema,
    entrypoints: ["Node"],
    module_prefix: "MyApp.Schema"
  )
end
```

Definition names infer NIF names such as `decode_node`. For Rustler projects,
prefer keeping the native API list in one non-Rustler metadata module:

```elixir
defmodule MyApp.Native.Nifs do
  @moduledoc "Native NIF stubs exposed by MyApp."

  @stubs [decode_node: 1, decode_image: 1]

  def stubs, do: @stubs
end
```

Then use the same metadata from `rustq.exs`:

```elixir
generate :native_decoders, "native/my_nif/src/generated.rs" do
  content KiwiCodec.RustlerGenerator.source(schema,
    entrypoints: {:nif_stubs, MyApp.Native.Nifs},
    module_prefix: "MyApp.Schema"
  )
end
```

The generated file includes Rustler imports, RustQ-provided atom/struct helpers,
schema decoders, and requested NIF entrypoints. The native crate must provide the
Kiwi `Decoder` type used by the generated code; by default it is imported from
`crate::runtime::Decoder`, or pass `decoder: "some::path::Decoder"`.

## Containers

```elixir
binary = KiwiCodec.Container.build([KiwiCodec.Container.deflate("schema"), KiwiCodec.Container.deflate("data")])
parsed = KiwiCodec.Container.parse(binary)
```

## Benchmarks

```sh
elixir bench/codec_bench.exs
```

## Development

```sh
mix deps.get
mix ci
```

## Installation

Once published, add it to your dependencies:

```elixir
def deps do
  [
    {:kiwi_codec, "~> 0.1.1"}
  ]
end
```
