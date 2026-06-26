defmodule KiwiCodec.Schema.Binary.TypeIndexTest do
  use ExUnit.Case, async: true

  alias KiwiCodec.Schema.Binary.TypeIndex
  alias KiwiCodec.Schema.Field
  alias KiwiCodec.Schema.Message

  test "encodes primitive fields as bitwise-negated primitive indexes" do
    assert TypeIndex.encode(%Field{type: "bool"}, %{}) == -1
    assert TypeIndex.encode(%Field{type: "int"}, %{}) == -3
    assert TypeIndex.encode(%Field{type: "float"}, %{}) == -5
  end

  test "encodes schema references as definition indexes" do
    assert TypeIndex.encode(%Field{type: "Node"}, %{"Node" => 2}) == 2
  end

  test "decodes primitive and schema reference indexes" do
    definitions = [%Message{name: "Point"}, %Message{name: "Node"}]

    assert TypeIndex.decode(-1, definitions) == "bool"
    assert TypeIndex.decode(-5, definitions) == "float"
    assert TypeIndex.decode(1, definitions) == "Node"
  end
end
