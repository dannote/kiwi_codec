defmodule KiwiCodec.RustlerGenerator.RustExprTest do
  use ExUnit.Case, async: true

  alias KiwiCodec.RustlerGenerator.RustExpr

  test "renders primitive decoder expressions" do
    assert RustExpr.primitive("bool") == "decoder.read_bool()?"
    assert RustExpr.primitive("byte") == "decoder.read_byte()?"
    assert RustExpr.primitive("string") == "decoder.read_string(env)?"
    assert RustExpr.primitive("float") == "decoder.read_var_float(env)?"
    assert RustExpr.primitive("int") == "decoder.read_var_int()?"
    assert RustExpr.primitive("int64") == "decoder.read_var_int64()?"
    assert RustExpr.primitive("uint") == "decoder.read_var_uint()?"
    assert RustExpr.primitive("uint64") == "decoder.read_var_uint64()?"
    assert RustExpr.primitive("Point") == nil
  end

  test "normalizes Rust identifiers" do
    assert RustExpr.ident(:decode_node) == "decode_node"
    assert RustExpr.ident("dataBlob") == "data_blob"
    assert RustExpr.ident("Scene.Node") == "scene_node"
  end

  test "indents rendered iodata" do
    assert RustExpr.indent([], 4) == []
    assert RustExpr.indent(["one", "\n", "two"], 2) == "  one\n  two"
  end
end
