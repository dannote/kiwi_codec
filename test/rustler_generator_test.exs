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
      |> Keyword.take([
        :definitions,
        :entrypoints,
        :module_prefix,
        :decoder,
        :decoder_sources,
        :features,
        :sparse_messages
      ])
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
    assert generated =~ "macro_rules! kiwi_struct_decoder"
    assert generated =~ "macro_rules! kiwi_message_decoder"
    assert generated =~ "decoder.read_var_float(env)?"
    assert generated =~ "decoder.read_byte_array(env)?"
    assert generated =~ "decoder.read_var_uint()?"
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

  defmodule NativeStubMetadata do
    @moduledoc "Test NIF stub metadata module used for Rustler generator entrypoint inference."

    @stubs [decode_node: 1, decode_image: 1, decode_sparse_message: 1]

    def stubs, do: @stubs
  end

  test "infers entrypoints from an explicit NIF stub metadata module" do
    schema_source = """
    struct Node {
      uint id;
    }

    message Image {
      byte[] hash = 1;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        entrypoints: {:nif_stubs, NativeStubMetadata},
        module_prefix: "Example.Schema"
      )

    assert generated =~ "fn decode_image"
    assert generated =~ "fn decode_node"
    refute generated =~ "fn decode_sparse_message"
  end

  test "renders generic sparse and skip decoder families through feature options" do
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
      string name = 2;
      Point origin = 3;
      Kind kind = 4;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Image"],
        features: [:sparse, :skip],
        module_prefix: "Example.Schema"
      )

    refute generated =~ "macro_rules! kiwi_message_decoder"
    assert generated =~ "macro_rules! kiwi_sparse_message_decoder"
    assert generated =~ "kiwi_sparse_message_decoder!"
    assert generated =~ "fn decode_sparse_image_from_decoder"
    assert generated =~ "fn skip_image_from_decoder"
    assert generated =~ "fn skip_point_from_decoder"
    assert generated =~ "kiwi_skip_message_decoder!"
    assert generated =~ "1 => bytes kiwi_skip_bytes_value;"
    assert generated =~ "2 => one kiwi_skip_string_value;"
    assert generated =~ "3 => one skip_point_from_decoder;"
    assert generated =~ "4 => one kiwi_skip_uint_value;"
    refute generated =~ "fn skip_kind_from_decoder"
    assert generated =~ "kiwi_skip_struct_decoder!"
    assert generated =~ "one kiwi_skip_float_value;"
    refute generated =~ "fn decode_image_from_decoder<'a>"
  end

  test "renders descriptor-backed sparse message decoders when requested" do
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
      string name = 2;
      Point origin = 3;
      Kind kind = 4;
      bool visible = 5;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Image"],
        features: [:sparse, :skip],
        sparse_messages: :descriptor,
        module_prefix: "Example.Schema",
        decoder_sources: ["test/fixtures/decoder_runtime.rs"]
      )

    assert generated =~ "macro_rules! kiwi_sparse_skip_message_descriptor_decoder"
    assert generated =~ "kiwi_sparse_skip_message_descriptor_decoder!"
    refute generated =~ "macro_rules! kiwi_sparse_message_decoder"
    refute generated =~ "macro_rules! kiwi_skip_message_decoder"
    assert generated =~ "1 => \"hash\": one kiwi_sparse_bytes_value;"
    assert generated =~ "2 => \"name\": one kiwi_sparse_string_value;"
    assert generated =~ "3 => \"origin\": one decode_sparse_point_from_decoder;"
    assert generated =~ "4 => \"kind\": one decode_sparse_kind_from_decoder;"
    assert generated =~ "5 => \"visible\": one kiwi_sparse_bool_value;"
    assert generated =~ "let value = decoder.read_bool()?;"
    assert generated =~ "macro_rules! kiwi_sparse_repeated"
    refute generated =~ "bytes kiwi_sparse_bytes_value"
    refute generated =~ "enum KiwiSparseKind"
    refute generated =~ "1 => \"hash\": decoder.read_byte_array(env)?;"
  end

  test "ignores decoder source metadata when skip decoders are not requested" do
    schema_source = """
    struct Node {
      uint id;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Node"],
        features: [:full],
        module_prefix: "Example.Schema",
        decoder_sources: ["test/fixtures/missing_decoder_runtime.rs"]
      )

    assert generated =~ "fn decode_node_from_decoder"
    assert generated =~ "decoder.read_var_uint()?"
  end

  test "uses decoder source metadata for defrust-authored skip helpers" do
    schema_source = """
    message Image {
      int64 offset = 1;
      string name = 2;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Image"],
        features: [:skip],
        module_prefix: "Example.Schema",
        decoder_sources: ["test/fixtures/decoder_runtime.rs"]
      )

    assert generated =~ "fn kiwi_skip_int64_value(decoder: &mut Decoder<'_>) -> NifResult<()>"
    assert generated =~ "decoder.read_var_int64()?;"
    assert generated =~ "fn kiwi_skip_string_value(decoder: &mut Decoder<'_>) -> NifResult<()>"
    assert generated =~ "decoder.skip_string()?;"
    refute generated =~ "unwrap!"
    refute generated =~ "match decoder.read_var_int64()"
  end

  test "sparse enum decoders delegate to full enum decoders when full decoders are present" do
    schema_source = """
    enum Kind {
      Rectangle = 1;
    }

    message Image {
      Kind kind = 1;
    }
    """

    {generated, _config} =
      generate_with_rustq_gen!(schema_source,
        definitions: ["Image"],
        features: [:full, :sparse],
        module_prefix: "Example.Schema"
      )

    assert generated =~ "fn decode_kind_from_decoder;"

    assert generated =~
             "fn decode_sparse_kind_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>>"

    assert generated =~ "decode_kind_from_decoder(env, decoder)"

    assert generated =~
             "1 => \"kind\": decode_sparse_kind_from_decoder(env, decoder)?.encode(env);"
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

    refute generated =~ "static KIND_ATOM_0: OnceLock<Atom> = OnceLock::new();"
    assert generated =~ "1 => \"rectangle\";"
    assert generated =~ "static POINT_MODULE_ATOM: OnceLock<Atom> = OnceLock::new();"
    assert generated =~ "static NODE_STRUCT_KEYS: OnceLock<Vec<rustler::wrapper::NIF_TERM>>"
    assert generated =~ "kiwi_enum_decoder!"
    assert generated =~ "fn decode_kind_from_decoder;"
    assert generated =~ "match decoder.read_var_uint()? as i64"
    assert generated =~ "kiwi_struct_decoder!"
    assert generated =~ "fn decode_node_from_decoder;"
    refute generated =~ "static MODULE_ATOM: OnceLock<Atom>"
    refute generated =~ "static ATOM_0: OnceLock<Atom>"
  end
end
