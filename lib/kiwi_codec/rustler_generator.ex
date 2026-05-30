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
    "bool" => "read_bool",
    "byte" => "read_byte",
    "float" => "read_var_float_value",
    "int" => "read_var_int",
    "int64" => "read_var_int64",
    "string" => "read_string",
    "uint" => "read_var_uint",
    "uint64" => "read_var_uint64"
  }

  @type entrypoint :: {atom() | String.t(), String.t()}

  @doc """
  Renders a Rust template with generated Kiwi decoder replacements.

  Currently generates native decoders for struct definitions with primitive
  fields. This is enough to validate the template pipeline and Rustler term
  construction before expanding to messages and nested schema types.
  """
  @spec render!(Schema.t(), keyword()) :: Path.t()
  def render!(%Schema{} = schema, opts) do
    definitions = Keyword.get(opts, :definitions, [])
    entrypoints = Keyword.get(opts, :entrypoints, [])
    module_prefix = Keyword.fetch!(opts, :module_prefix)
    template = Keyword.fetch!(opts, :template)
    out = Keyword.fetch!(opts, :out)

    selected = select_definitions(schema, definitions)

    KiwiCodec.RustTemplate.render!(
      template,
      out,
      [
        {"kiwi_codegen::definitions", definitions_code(selected, module_prefix)},
        {"kiwi_codegen::entrypoints", entrypoints_code(entrypoints)}
      ]
    )
  end

  defp select_definitions(%Schema{} = schema, []), do: schema.definitions

  defp select_definitions(%Schema{} = schema, names) do
    names = MapSet.new(Enum.map(names, &to_string/1))
    Enum.filter(schema.definitions, &MapSet.member?(names, &1.name))
  end

  defp definitions_code(definitions, module_prefix) do
    definitions
    |> Enum.map(&definition_code(&1, module_prefix))
    |> Enum.reject(&(&1 == nil))
    |> Enum.join("\n\n")
  end

  defp definition_code(%Definition{kind: :struct} = definition, module_prefix) do
    fields = Enum.map(definition.fields, &struct_field_decode/1)

    """
    fn #{decoder_name(definition.name)}_from_decoder<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        let mut term = rustler::types::elixir_struct::make_ex_struct(env, #{rust_string(module_name(module_prefix, definition.name))})?;
    #{indent(fields, 4)}
        Ok(term)
    }
    """
  end

  defp definition_code(_definition, _module_prefix), do: nil

  defp struct_field_decode(field) do
    decoder = Map.fetch!(@primitive_decoders, field.type)
    field_name = field_name(field.name)

    value =
      if field.array? do
        "decoder.read_repeated(|decoder| decoder.#{decoder}())?"
      else
        "decoder.#{decoder}()?"
      end

    """
    let value = #{value};
    term = term.map_put(Atom::from_str(env, #{rust_string(field_name)})?, value)?;
    """
  end

  defp entrypoints_code(entrypoints) do
    Enum.map_join(entrypoints, "\n\n", fn {nif_name, definition_name} ->
      """
      #[rustler::nif(schedule = "DirtyCpu")]
      pub fn #{nif_name}<'a>(env: Env<'a>, bytes: Binary<'a>) -> NifResult<Term<'a>> {
          let mut decoder = Decoder::new(bytes.as_slice());
          let term = #{decoder_name(definition_name)}_from_decoder(env, &mut decoder)?;
          decoder.finish()?;
          Ok(term)
      }
      """
    end)
  end

  defp decoder_name(name), do: "decode_#{rust_ident(name)}"

  defp module_name(module_prefix, name) do
    "Elixir.#{module_prefix}.#{name}"
  end

  defp field_name(name), do: Macro.underscore(name)

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
