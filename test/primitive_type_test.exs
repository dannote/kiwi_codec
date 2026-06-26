defmodule KiwiCodec.PrimitiveTypeTest do
  use ExUnit.Case, async: true

  alias KiwiCodec.PrimitiveType

  test "recognizes schema primitive names" do
    assert PrimitiveType.name?("uint64")
    refute PrimitiveType.name?("Node")
  end

  test "maps schema primitive names to generated module atoms" do
    assert PrimitiveType.to_atom!("bool") == :bool
    assert PrimitiveType.to_atom!("float") == :float
    assert PrimitiveType.to_atom!("uint64") == :uint64
  end

  test "recognizes generated primitive atoms" do
    assert PrimitiveType.atom?(:string)
    refute PrimitiveType.atom?(:not_a_kiwi_primitive)
  end

  test "owns binary schema primitive ordering" do
    assert PrimitiveType.binary_schema_index("bool") == 0
    assert PrimitiveType.binary_schema_index("int") == 2
    assert PrimitiveType.binary_schema_index("float") == 4
    assert PrimitiveType.binary_schema_name!(7) == "uint64"
  end
end
