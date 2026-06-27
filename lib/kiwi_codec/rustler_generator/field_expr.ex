defmodule KiwiCodec.RustlerGenerator.FieldExpr do
  @moduledoc """
  Builds Rusty-Elixir expressions for decoding Kiwi fields in generated Rustler code.
  """

  alias KiwiCodec.RustlerGenerator.Name
  alias KiwiCodec.RustlerGenerator.RustExpr

  def primitive(%{type: type}), do: RustExpr.primitive_ast(type)
  def primitive(_field), do: nil

  @spec build(map(), map()) :: Macro.t()
  def build(%{array?: true, type: "byte"}, _definition_map) do
    quote(do: decoder.read_byte_array(env))
  end

  def build(%{array?: true} = field, definition_map) do
    inner = result(%{field | array?: false}, definition_map)

    quote do
      decoder.read_repeated(fn decoder -> unquote(inner) end)
    end
  end

  def build(field, definition_map), do: result(field, definition_map)

  defp result(field, definition_map) do
    primitive(field) ||
      field
      |> referenced_definition!(definition_map)
      |> then(fn definition ->
        name = Name.decoder_function(definition.name)

        quote do
          unquote(name)(env, decoder)
        end
      end)
  end

  defp referenced_definition!(field, definition_map), do: Map.fetch!(definition_map, field.type)
end
