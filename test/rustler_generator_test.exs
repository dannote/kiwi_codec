defmodule KiwiCodec.RustlerGeneratorTest do
  use ExUnit.Case, async: true

  test "renders struct decoder and entrypoint into Rust template" do
    schema =
      KiwiCodec.parse_schema!("""
      struct Point {
        float x;
        float y;
      }
      """)

    dir =
      Path.join(
        System.tmp_dir!(),
        "kiwi-rustler-generator-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    template = Path.join(dir, "template.rs")
    out = Path.join(dir, "generated.rs")

    File.write!(template, """
    use rustler::{Binary, Env, NifResult, Term};
    use rustler::types::atom::Atom;
    use crate::runtime::Decoder;

    kiwi_codegen::definitions!();
    kiwi_codegen::entrypoints!();
    """)

    KiwiCodec.RustlerGenerator.render!(schema,
      definitions: ["Point"],
      entrypoints: [decode_point: "Point"],
      module_prefix: "Example.Schema",
      template: template,
      out: out
    )

    generated = File.read!(out)

    assert generated =~ "fn decode_point_from_decoder"
    assert generated =~ "pub fn decode_point"
    assert generated =~ ~s("Elixir.Example.Schema.Point")
    assert generated =~ "decoder.read_var_float_value()?"
    refute generated =~ "kiwi_codegen"
  end
end
