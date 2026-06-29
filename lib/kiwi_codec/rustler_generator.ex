defmodule KiwiCodec.RustlerGenerator do
  @moduledoc """
  Generates Rustler decoder code from Kiwi schemas for RustQ manifests.

  This is an experimental bridge for optional native backends. It generates a
  complete Rust source file for schema-dependent decoder functions and NIF
  entrypoints; `rustq.exs` owns writing and freshness checks.

  The generated source includes the Rustler imports, RustQ Rustler term helpers,
  schema decoders, and requested entrypoints. The caller only needs to provide a
  `Decoder<'a>` type with Kiwi primitive reader methods.
  """

  alias KiwiCodec.RustlerGenerator.Definition
  alias KiwiCodec.RustlerGenerator.Entrypoint
  alias KiwiCodec.RustlerGenerator.Selection
  alias KiwiCodec.RustlerGenerator.Skip
  alias KiwiCodec.RustlerGenerator.Sparse
  alias KiwiCodec.RustlerGenerator.Splice
  alias KiwiCodec.Schema
  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A

  @type entrypoint :: Entrypoint.entrypoint()

  @doc """
  Returns a complete Rust source file for generated Rustler decoders.

      generate :native_decoders, "native/my_nif/src/generated.rs" do
        schema = KiwiCodec.parse_schema!(File.read!("priv/schema.kiwi"))

        content KiwiCodec.RustlerGenerator.source(schema,
          entrypoints: ["Node"],
          module_prefix: "Example.Schema"
        )
      end

  Options:

    * `:definitions` - schema definition names to generate, including their
      dependencies. Defaults to the requested entrypoint definitions, or all
      definitions when no entrypoints are requested.
    * `:entrypoints` - `:all`, `{:nif_stubs, module}`, a NIF stub module,
      definition names, or `{nif_name, definition_name}` entries for generated
      NIFs. Definition names infer `decode_<definition_name>` NIFs. `:all`
      generates one inferred NIF for every schema definition. A NIF stub module
      infers entries from one-arity `decode_*` stubs whose suffix matches a schema
      definition. For `{:nif_stubs, module}`, the module must expose `stubs/0`.
    * `:module_prefix` - Elixir module prefix for decoded structs.
    * `:decoder` - Rust path imported as `Decoder`. Defaults to
      `"crate::runtime::Decoder"`.
    * `:decoder_sources` - Rust source file or files that define the imported
      `Decoder`. When provided, shared skip helper functions are authored with
      `defrust` and RustQ uses the real decoder method metadata for propagation.
    * `:features` - decoder families to generate. Defaults to `[:full]`.
      Use `:sparse` and `:skip` for generic sparse map decoders and skip
      helpers used by projection-oriented native backends.
    * `:sparse_messages` - sparse message generation strategy. Defaults to
      `:match`. Use `:descriptor` to generate compact descriptor-backed sparse
      message decoders and benchmark before adopting on hot schemas.

  """
  @spec source(Schema.t(), keyword()) :: String.t()
  def source(%Schema{} = schema, opts) do
    [source_prelude(opts), generated_fragments(schema, opts)]
    |> List.flatten()
    |> Enum.map_join("\n\n", &Rust.to_fragment/1)
    |> Kernel.<>("\n")
  end

  defp generated_fragments(%Schema{} = schema, opts) do
    entrypoints = opts |> Keyword.get(:entrypoints, []) |> normalize_entrypoints(schema)
    definitions = Keyword.get(opts, :definitions, inferred_definitions(entrypoints))
    module_prefix = Keyword.fetch!(opts, :module_prefix)

    definition_map = Selection.definition_map(schema)
    selected = Selection.definitions(schema, definitions, definition_map)

    features = Keyword.get(opts, :features, [:full])

    [
      Splice.rustler_helpers(opts),
      feature_fragments(features, selected, module_prefix, definition_map, opts),
      Entrypoint.fragments(entrypoints)
    ]
  end

  defp feature_fragments(features, selected, module_prefix, definition_map, opts) do
    shared_sparse_skip? =
      :sparse in features and :skip in features and
        Keyword.get(opts, :sparse_messages, :match) == :descriptor

    Enum.flat_map(features, fn
      :full ->
        Definition.fragments(selected, module_prefix, definition_map)

      :sparse ->
        Sparse.fragments(selected, module_prefix, definition_map,
          full?: :full in features,
          struct_mode:
            if(Keyword.get(opts, :decoder_sources, []) == [], do: :match, else: :descriptor),
          message_mode:
            if(shared_sparse_skip?,
              do: :descriptor_with_skip,
              else: Keyword.get(opts, :sparse_messages, :match)
            )
        )

      :skip ->
        Skip.fragments(selected, definition_map, messages?: not shared_sparse_skip?)

      feature ->
        raise ArgumentError, "unknown Rustler generator feature #{inspect(feature)}"
    end)
  end

  defp normalize_entrypoints(:all, %Schema{} = schema) do
    schema.definitions
    |> Enum.map(& &1.name)
    |> normalize_entrypoints(schema)
  end

  defp normalize_entrypoints({:nif_stubs, module}, %Schema{} = schema) when is_atom(module) do
    Code.ensure_loaded!(module)

    unless function_exported?(module, :stubs, 0) do
      raise ArgumentError, "expected #{inspect(module)} to expose stubs/0"
    end

    module.stubs() |> entrypoints_from_exports(schema)
  end

  defp normalize_entrypoints(module, %Schema{} = schema) when is_atom(module) do
    Code.ensure_loaded!(module)
    module.module_info(:exports) |> entrypoints_from_exports(schema)
  end

  defp normalize_entrypoints(entrypoints, %Schema{}) do
    Enum.map(entrypoints, fn
      {nif_name, definition_name} -> {nif_name, to_string(definition_name)}
      definition_name -> {inferred_entrypoint_name(definition_name), to_string(definition_name)}
    end)
  end

  defp entrypoints_from_exports(exports, %Schema{} = schema) do
    definitions_by_underscore = Map.new(schema.definitions, &{Macro.underscore(&1.name), &1.name})

    exports
    |> Enum.flat_map(fn
      {name, 1} -> entrypoint_from_export(name, definitions_by_underscore)
      _export -> []
    end)
    |> Enum.sort_by(fn {nif_name, _definition_name} -> to_string(nif_name) end)
  end

  defp entrypoint_from_export(name, definitions_by_underscore) do
    name = to_string(name)

    with "decode_" <> suffix <- name,
         {:ok, definition_name} <- Map.fetch(definitions_by_underscore, suffix) do
      [{name, definition_name}]
    else
      _other -> []
    end
  end

  defp inferred_entrypoint_name(definition_name) do
    definition_name
    |> to_string()
    |> Macro.underscore()
    |> then(&"decode_#{&1}")
  end

  defp inferred_definitions([]), do: []

  defp inferred_definitions(entrypoints) do
    Enum.map(entrypoints, fn {_nif_name, definition_name} -> definition_name end)
  end

  defp source_prelude(opts) do
    decoder = Keyword.get(opts, :decoder, "crate::runtime::Decoder")

    [
      A.use([:rustler, :types, :atom, :Atom]),
      A.use({[:rustler], [:Binary, :Encoder, :Env, :Error, :NifResult, :Term]}),
      A.use({[:std, :sync], [:OnceLock]}),
      A.use(decoder)
    ]
    |> Rust.ast_items()
  end
end
