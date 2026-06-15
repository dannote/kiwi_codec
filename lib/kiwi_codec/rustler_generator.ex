defmodule KiwiCodec.RustlerGenerator do
  @moduledoc """
  Generates Rustler decoder code from Kiwi schemas using Rust templates.

  This is an experimental bridge for optional native backends. It keeps Rust
  runtime code in real Rust templates and only generates schema-dependent
  decoder functions and NIF entrypoints.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.Definition

  @primitive_decoders %{
    "bool" => "read_bool()",
    "byte" => "read_byte()",
    "float" => "read_var_float(env)",
    "int" => "read_var_int()",
    "int64" => "read_var_int64()",
    "string" => "read_string(env)",
    "uint" => "read_var_uint()",
    "uint64" => "read_var_uint64()"
  }

  @type entrypoint :: {atom() | String.t(), String.t()}

  @doc """
  Renders a Rust template with generated Kiwi decoder replacements.

  Generates native decoders for enums, structs, and messages.
  """
  @spec render!(Schema.t(), keyword()) :: Path.t()
  def render!(%Schema{} = schema, opts) do
    template = Keyword.fetch!(opts, :template)
    out = Keyword.fetch!(opts, :out)

    KiwiCodec.RustTemplate.render!(template, out, replacements(schema, opts), opts)
  end

  @doc """
  Renders a Rust template with generated Kiwi decoder replacements and returns source.

  Accepts the same options as `render!/2`, except `:out` is not required.
  """
  @spec render_source!(Schema.t(), keyword()) :: String.t()
  def render_source!(%Schema{} = schema, opts) do
    template = Keyword.fetch!(opts, :template)

    KiwiCodec.RustTemplate.render_source!(template, replacements(schema, opts), opts)
  end

  defp replacements(%Schema{} = schema, opts) do
    definitions = Keyword.get(opts, :definitions, [])
    entrypoints = Keyword.get(opts, :entrypoints, [])
    module_prefix = Keyword.fetch!(opts, :module_prefix)

    definition_map = Map.new(schema.definitions, &{&1.name, &1})
    selected = select_definitions(schema, definitions, definition_map)

    [
      {:definitions, definition_fragments(selected, module_prefix, definition_map)},
      {:entrypoints, entrypoint_fragments(entrypoints)}
    ] ++ Keyword.get(opts, :extra_splices, [])
  end

  defp select_definitions(%Schema{} = schema, [], _definition_map), do: schema.definitions

  defp select_definitions(%Schema{} = schema, names, definition_map) do
    names
    |> Enum.map(&to_string/1)
    |> include_dependencies(definition_map, MapSet.new())
    |> then(fn selected_names ->
      Enum.filter(schema.definitions, &MapSet.member?(selected_names, &1.name))
    end)
  end

  defp include_dependencies([], _definition_map, acc), do: acc

  defp include_dependencies([name | names], definition_map, acc) do
    if MapSet.member?(acc, name) do
      include_dependencies(names, definition_map, acc)
    else
      definition = Map.fetch!(definition_map, name)

      dependencies =
        definition.fields
        |> Enum.map(& &1.type)
        |> Enum.filter(&Map.has_key?(definition_map, &1))

      include_dependencies(names ++ dependencies, definition_map, MapSet.put(acc, name))
    end
  end

  defp definition_fragments(definitions, module_prefix, definition_map) do
    definitions
    |> Enum.map(&definition_fragment(&1, module_prefix, definition_map))
    |> Enum.reject(&(&1 == nil))
    |> Enum.map(&fragment_code/1)
  end

  defp definition_fragment(definition, module_prefix, definition_map) do
    definition
    |> definition_code(module_prefix, definition_map)
    |> rust_item_fragment()
  end

  defp definition_code(%Definition{kind: :enum} = definition, _module_prefix, _definition_map) do
    arms = definition.fields |> Enum.with_index() |> Enum.map(&enum_arm/1)

    """
    fn #{decoder_name(definition.name)}_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        match decoder.read_var_uint()? {
    #{indent(arms, 8)}
            value => Ok((value as i64).encode(env)),
        }
    }
    """
  end

  defp definition_code(%Definition{kind: :struct} = definition, module_prefix, definition_map) do
    fields = Enum.map(definition.fields, &struct_field_decode(&1, definition_map))

    """
    fn #{decoder_name(definition.name)}_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        static MODULE_ATOM: OnceLock<Atom> = OnceLock::new();
        static STRUCT_KEYS: OnceLock<Vec<rustler::wrapper::NIF_TERM>> = OnceLock::new();
        let module_atom = cached_atom(env, &MODULE_ATOM, #{rust_string(module_name(module_prefix, definition.name))});
        let keys = cached_struct_keys(env, &STRUCT_KEYS, &[#{field_names(definition.fields)}]);
        let mut values = Vec::with_capacity(keys.len());
        values.push(module_atom.as_c_arg());
    #{indent(fields, 4)}
        make_struct(env, keys, &values)
    }
    """
  end

  defp definition_code(%Definition{kind: :message} = definition, module_prefix, definition_map) do
    fields =
      definition.fields |> Enum.with_index() |> Enum.map(&message_field_arm(&1, definition_map))

    """
    fn #{decoder_name(definition.name)}_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        static MODULE_ATOM: OnceLock<Atom> = OnceLock::new();
        static STRUCT_KEYS: OnceLock<Vec<rustler::wrapper::NIF_TERM>> = OnceLock::new();
        let module_atom = cached_atom(env, &MODULE_ATOM, #{rust_string(module_name(module_prefix, definition.name))});
        let keys = cached_struct_keys(env, &STRUCT_KEYS, &[#{field_names(definition.fields)}]);
        let mut values = default_values(module_atom, keys.len() - 1);
        loop {
            match decoder.read_var_uint()? {
                0 => break,
    #{indent(fields, 12)}
                field => return Err(Error::Term(Box::new(format!("unknown field {} while decoding #{definition.name}", field)))),
            }
        }
        make_struct(env, keys, &values)
    }
    """
  end

  defp enum_arm({field, index}) do
    "#{field.value} => { static ATOM_#{index}: OnceLock<Atom> = OnceLock::new(); Ok(cached_atom(env, &ATOM_#{index}, #{rust_string(field_name(field.name))}).encode(env)) },"
  end

  defp struct_field_decode(field, definition_map) do
    value = field_value(field, definition_map)

    """
    let value = #{value};
    values.push(value.encode(env).as_c_arg());
    """
  end

  defp message_field_arm({field, index}, definition_map) do
    value = field_value(field, definition_map)

    """
    #{field.value} => {
        let value = #{value};
        values[#{index + 1}] = value.encode(env).as_c_arg();
    }
    """
  end

  defp field_value(%{array?: true, type: "byte"}, _definition_map) do
    "decoder.read_byte_array(env)?"
  end

  defp field_value(%{array?: true} = field, definition_map) do
    "decoder.read_repeated(|decoder| #{field_result(%{field | array?: false}, definition_map)})?"
  end

  defp field_value(field, definition_map), do: "#{field_result(field, definition_map)}?"

  defp field_result(field, definition_map) do
    cond do
      primitive = @primitive_decoders[field.type] ->
        "decoder.#{primitive}"

      definition = definition_map[field.type] ->
        "#{decoder_name(definition.name)}_from_decoder(env, decoder)"
    end
  end

  defp entrypoint_fragments(entrypoints) do
    Enum.map(entrypoints, fn {nif_name, definition_name} ->
      """
      #[rustler::nif(schedule = "DirtyCpu")]
      pub fn #{nif_name}<'a>(env: Env<'a>, bytes: Binary<'a>) -> NifResult<Term<'a>> {
          let mut decoder = Decoder::new(bytes.as_slice());
          let term = #{decoder_name(definition_name)}_from_decoder(env, &mut decoder)?;
          decoder.finish()?;
          Ok(term)
      }
      """
      |> rust_item_fragment()
      |> fragment_code()
    end)
  end

  defp rust_item_fragment(code) do
    RustQ.parse_fragment!(:item, code)
  end

  defp fragment_code(fragment) do
    RustQ.Rust.to_fragment(fragment)
  end

  defp decoder_name(name), do: "decode_#{rust_ident(name)}"

  defp module_name(module_prefix, name) do
    "Elixir.#{module_prefix}.#{name}"
  end

  defp field_name(name), do: Macro.underscore(name)

  defp field_names(fields) do
    Enum.map_join(fields, ", ", fn field -> field.name |> field_name() |> rust_string() end)
  end

  defp rust_ident(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  defp rust_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "\"#{escaped}\""
  end

  defp indent(lines, spaces) when is_list(lines) do
    lines |> Enum.join("\n") |> indent(spaces)
  end

  defp indent(text, spaces) do
    padding = String.duplicate(" ", spaces)

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end
end
