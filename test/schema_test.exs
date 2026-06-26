defmodule KiwiCodec.SchemaTest do
  use ExUnit.Case, async: true

  alias KiwiCodec.Schema.Binary
  alias KiwiCodec.Schema.Parser

  @schema_text """
  enum NodeType {
    NONE = 0;
    FRAME = 4;
  }

  struct Vector {
    float x;
    float y;
  }

  message NodeChange {
    uint id = 1;
    string name = 2;
    NodeType type = 3;
    Vector position = 4;
    uint[] children = 5;
    byte[] blob = 6;
  }
  """

  test "parses schema definitions" do
    schema = Parser.parse!(@schema_text)

    assert Enum.map(schema.definitions, & &1.name) == ["NodeType", "Vector", "NodeChange"]

    [variant | _] = hd(schema.definitions).fields
    assert %KiwiCodec.Schema.EnumVariant{name: "NONE", value: 0} = variant

    assert [id | _] = List.last(schema.definitions).fields
    assert %KiwiCodec.Schema.Field{name: "id", id: 1} = id
  end

  test "round-trips binary schema" do
    schema = Parser.parse!(@schema_text)

    assert clear_locations(Binary.decode(Binary.encode(schema))) == clear_locations(schema)
  end

  test "rejects unexpected schema characters" do
    assert_raise ArgumentError, ~r/unexpected input at 1:26, got "@"/, fn ->
      Parser.parse!("message A { uint id = 1; @ }")
    end
  end

  test "raises decode errors for malformed binary schemas" do
    assert_raise KiwiCodec.DecodeError, ~r/invalid definition kind/, fn ->
      Binary.decode(<<1, "A", 0, 255, 0>>)
    end

    assert_raise KiwiCodec.DecodeError, ~r/unterminated string/, fn ->
      Binary.decode(<<1, "A">>)
    end

    assert_raise KiwiCodec.DecodeError, ~r/invalid binary schema/, fn ->
      Binary.decode(<<1, "A", 0, 1, 1, "x", 0, 18, 0, 1>>)
    end
  end

  test "schema interpreter encode and decode" do
    schema = Parser.parse!(@schema_text)

    value = %{
      "id" => 42,
      "name" => "hello",
      "type" => "FRAME",
      "position" => %{"x" => 1.5, "y" => -2.25},
      "children" => [1, 2, 300],
      "blob" => <<1, 2, 3>>
    }

    binary = KiwiCodec.SchemaInterpreter.encode(schema, "NodeChange", value)

    assert KiwiCodec.SchemaInterpreter.decode(schema, "NodeChange", binary) == value
  end

  defp clear_locations(schema) do
    update_in(schema.definitions, fn definitions ->
      Enum.map(definitions, fn definition ->
        fields = Enum.map(definition.fields, &%{&1 | line: 0, column: 0})
        %{definition | fields: fields, line: 0, column: 0}
      end)
    end)
  end
end
