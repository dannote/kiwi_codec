defmodule KiwiCodec.RustlerGeneratorTest do
  use ExUnit.Case, async: true

  test "renders struct decoder and entrypoint into Rust template" do
    schema =
      KiwiCodec.parse_schema!("""
      enum Kind {
        Rectangle = 1;
      }

      struct Point {
        float x;
        float y;
      }

      struct Node {
        Kind kind;
        Point position;
      }

      message Image {
        byte[] hash = 1;
        string name = 2;
        uint dataBlob = 3;
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

    __rq_definitions!();
    __rq_entrypoints!();
    """)

    KiwiCodec.RustlerGenerator.render!(schema,
      definitions: ["Node", "Image"],
      entrypoints: [decode_node: "Node", decode_image: "Image"],
      module_prefix: "Example.Schema",
      template: template,
      out: out
    )

    generated = File.read!(out)

    generated_source =
      KiwiCodec.RustlerGenerator.render_source!(schema,
        definitions: ["Node", "Image"],
        entrypoints: [decode_node: "Node", decode_image: "Image"],
        module_prefix: "Example.Schema",
        template: template
      )

    assert generated_source == generated
    assert generated =~ "fn decode_node_from_decoder"
    assert generated =~ "fn decode_point_from_decoder"
    assert generated =~ "fn decode_kind_from_decoder"
    assert generated =~ "pub fn decode_node"
    assert generated =~ "pub fn decode_image"
    assert generated =~ ~s("Elixir.Example.Schema.Node")
    assert generated =~ ~s("Elixir.Example.Schema.Image")
    assert generated =~ "decoder.read_var_float(env)?"
    assert generated =~ "decoder.read_byte_array(env)?"
    assert generated =~ "match decoder.read_var_uint()?"
    refute generated =~ "__rq_"
  end

  test "passes render options through to RustQ" do
    schema =
      KiwiCodec.parse_schema!("""
      struct Point {
        float x;
      }
      """)

    dir =
      Path.join(
        System.tmp_dir!(),
        "kiwi-rustler-generator-options-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    template = Path.join(dir, "template.rs")

    File.write!(template, """
    use rustler::{Env, NifResult, Term};
    use rustler::types::atom::Atom;
    use crate::runtime::Decoder;
    __rq_definitions!();
    """)

    generated =
      KiwiCodec.RustlerGenerator.render_source!(schema,
        definitions: ["Point"],
        module_prefix: "Example.Schema",
        template: template,
        rustfmt: true
      )

    assert generated =~ "fn decode_point_from_decoder<'a>("
  end
end
