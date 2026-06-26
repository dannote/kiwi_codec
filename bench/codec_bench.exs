Mix.install(
  [
    {:kiwi_codec, path: Path.expand("..", __DIR__)}
  ],
  consolidate_protocols: false
)

defmodule BenchSchema.Kind do
  use KiwiCodec, kind: :enum

  enum_value :node, 1
end

defmodule BenchSchema.Point do
  use KiwiCodec, kind: :struct

  field :x, 1, type: :float
  field :y, 2, type: :float
end

defmodule BenchSchema.Node do
  use KiwiCodec, kind: :message

  field :id, 1, type: :uint
  field :kind, 2, type: {:enum, BenchSchema.Kind}
  field :name, 3, type: :string
  field :position, 4, type: BenchSchema.Point
end

schema_text = """
enum Kind { NODE = 1; }
struct Point { float x; float y; }
message Node { uint id = 1; Kind kind = 2; string name = 3; Point position = 4; }
"""

schema = KiwiCodec.parse_schema!(schema_text)
static_value = struct(BenchSchema.Node, id: 1, kind: :node, name: "demo", position: struct(BenchSchema.Point, x: 1.0, y: 2.0))
runtime_value = %{"id" => 1, "kind" => "NODE", "name" => "demo", "position" => %{"x" => 1.0, "y" => 2.0}}
static_binary = KiwiCodec.encode(static_value)
runtime_binary = KiwiCodec.SchemaInterpreter.encode(schema, "Node", runtime_value)

jobs = %{
  "static encode" => fn -> KiwiCodec.encode(static_value) end,
  "static decode" => fn -> KiwiCodec.decode(static_binary, BenchSchema.Node) end,
  "runtime encode" => fn -> KiwiCodec.SchemaInterpreter.encode(schema, "Node", runtime_value) end,
  "runtime decode" => fn -> KiwiCodec.SchemaInterpreter.decode(schema, "Node", runtime_binary) end
}

if Code.ensure_loaded?(Benchee) do
  Benchee.run(jobs)
else
  Enum.each(jobs, fn {name, fun} ->
    {microseconds, _result} = :timer.tc(fn -> for _ <- 1..100_000, do: fun.() end)
    IO.puts("#{name}: #{microseconds / 100_000} µs/op")
  end)
end
