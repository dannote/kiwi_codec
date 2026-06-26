defmodule KiwiCodec.RustlerGeneratorTest do
  use ExUnit.Case, async: true

  defp generate_with_rustq_gen!(schema_source, opts) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "kiwi-rustq-gen-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    out = Path.join(dir, "generated.rs")
    config = Path.join(dir, "rustq.exs")

    generator_opts =
      opts
      |> Keyword.take([:definitions, :entrypoints, :module_prefix, :decoder])
      |> inspect(limit: :infinity)

    File.write!(config, """
    use RustQ.Config

    schema = KiwiCodec.parse_schema!(#{inspect(schema_source)})

    generate :generated, #{inspect(out)} do
      content KiwiCodec.RustlerGenerator.source(schema, #{generator_opts})
    end
    """)

    Mix.Task.reenable("rustq.gen")
    Mix.Task.run("rustq.gen", ["--config", config])
    Mix.Task.reenable("rustq.gen")

    {File.read!(out), config}
  end

  test "renders struct decoder and entrypoint through rustq.gen without caller templates" do
    schema_source = """
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
    """

    {generated, config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Node", "Image"],
        entrypoints: [decode_node: "Node", decode_image: "Image"],
        module_prefix: "Example.Schema"
      )

    Mix.Task.run("rustq.gen", ["--check", "--config", config])
    Mix.Task.reenable("rustq.gen")

    assert generated =~ "use rustler::types::atom::Atom;"
    assert generated =~ "use crate::runtime::Decoder;"
    assert generated =~ "fn cached_struct_keys"
    assert generated =~ "fn make_struct_from_nif_term_arrays"
    assert generated =~ "fn decode_node_from_decoder"
    assert generated =~ "fn decode_point_from_decoder"
    assert generated =~ "fn decode_kind_from_decoder"
    assert generated =~ "fn decode_node"
    assert generated =~ "fn decode_image"
    assert generated =~ "match decode_node_from_decoder(env, &mut decoder)"
    refute generated =~ "let term = decode_node(env, &mut decoder)?"
    assert generated =~ ~s("Elixir.Example.Schema.Node")
    assert generated =~ ~s("Elixir.Example.Schema.Image")
    assert generated =~ "match decoder.read_var_float(env)"
    assert generated =~ "match decoder.read_byte_array(env)"
    assert generated =~ "match decoder.read_var_uint()"
    refute generated =~ "__rq_"
  end

  test "infers entrypoint NIF names and selected definitions from definition names" do
    schema_source = """
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
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        entrypoints: ["Node", "Image"],
        module_prefix: "Example.Schema"
      )

    assert generated =~ "fn decode_node"
    assert generated =~ "fn decode_image"
    assert generated =~ "fn decode_node_from_decoder"
    assert generated =~ "fn decode_image_from_decoder"
    assert generated =~ "fn decode_point_from_decoder"
    assert generated =~ "fn decode_kind_from_decoder"
  end

  defmodule NativeStubs do
    @moduledoc "Test NIF stub module used for Rustler generator entrypoint inference."

    def decode_image(_binary), do: :erlang.nif_error(:nif_not_loaded)
    def decode_node(_binary), do: :erlang.nif_error(:nif_not_loaded)
    def decode_sparse_message(_binary), do: :erlang.nif_error(:nif_not_loaded)
  end

  test "infers entrypoints from exported NIF stubs matching schema definitions" do
    schema_source = """
    struct Node {
      uint id;
    }

    message Image {
      byte[] hash = 1;
    }

    message Message {
      Node node = 1;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        entrypoints: NativeStubs,
        module_prefix: "Example.Schema"
      )

    assert generated =~ "fn decode_image"
    assert generated =~ "fn decode_node"
    refute generated =~ "fn decode_message<'a>"
    refute generated =~ "fn decode_sparse_message"
  end

  test "infers entrypoints from a NIF stub source file without loading the module" do
    schema_source = """
    struct Node {
      uint id;
    }

    message Image {
      byte[] hash = 1;
    }
    """

    dir = Path.join(System.tmp_dir!(), "kiwi-nif-stubs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    stubs_path = Path.join(dir, "nif.ex")

    File.write!(stubs_path, """
    defmodule Example.Nif do
      @stubs [decode_node: 1, decode_image: 1, decode_sparse_message: 1]
    end
    """)

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        entrypoints: {:nif_stubs, stubs_path},
        module_prefix: "Example.Schema"
      )

    assert generated =~ "fn decode_image"
    assert generated =~ "fn decode_node"
    refute generated =~ "fn decode_sparse_message"
  end

  test "infers entrypoints for every schema definition" do
    schema_source = """
    enum Kind {
      Rectangle = 1;
    }

    struct Point {
      float x;
      float y;
    }

    message Image {
      byte[] hash = 1;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        entrypoints: :all,
        module_prefix: "Example.Schema"
      )

    assert generated =~ "fn decode_kind"
    assert generated =~ "fn decode_point"
    assert generated =~ "fn decode_image"
  end

  test "renders enum and struct decoders from schema-specific RustQ items" do
    schema_source = """
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
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Node"],
        module_prefix: "Example.Schema"
      )

    assert generated =~ "static KIND_ATOM_0: OnceLock<Atom> = OnceLock::new();"
    assert generated =~ "static POINT_MODULE_ATOM: OnceLock<Atom> = OnceLock::new();"
    assert generated =~ "static NODE_STRUCT_KEYS: OnceLock<Vec<rustler::wrapper::NIF_TERM>>"
    assert generated =~ "fn decode_kind_from_decoder<'a>"
    assert generated =~ "match decoder.read_var_uint()"
    assert generated =~ "match raw as i64"
    assert generated =~ "fn decode_node_from_decoder<'a>"
    refute generated =~ "static MODULE_ATOM: OnceLock<Atom>"
    refute generated =~ "static ATOM_0: OnceLock<Atom>"
  end
end
