defmodule KiwiCodec.RustlerGenerator.FieldExpr do
  @moduledoc """
  Builds Rusty-Elixir expressions for decoding Kiwi fields in generated Rustler code.
  """

  alias KiwiCodec.RustlerGenerator.Name

  @primitive_decoders [
    {"bool", :read_bool, []},
    {"byte", :read_byte, []},
    {"float", :read_var_float, [:env]},
    {"int", :read_var_int, []},
    {"int64", :read_var_int64, []},
    {"string", :read_string, [:env]},
    {"uint", :read_var_uint, []},
    {"uint64", :read_var_uint64, []}
  ]

  for {type, method, args} <- @primitive_decoders do
    call =
      quote do
        decoder.unquote(method)(unquote_splicing(Enum.map(args, &Macro.var(&1, nil))))
      end

    def primitive(%{type: unquote(type)}) do
      unquote(Macro.escape(call))
    end
  end

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
