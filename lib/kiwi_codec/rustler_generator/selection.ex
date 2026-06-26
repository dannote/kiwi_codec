defmodule KiwiCodec.RustlerGenerator.Selection do
  @moduledoc """
  Selects schema definitions and their dependencies for Rustler generation.
  """

  alias KiwiCodec.Schema

  @spec definition_map(Schema.t()) :: %{String.t() => Schema.Definition.t()}
  def definition_map(%Schema{} = schema), do: Map.new(schema.definitions, &{&1.name, &1})

  @spec definitions(Schema.t(), [atom() | String.t()], map()) :: [Schema.Definition.t()]
  def definitions(%Schema{} = schema, [], _definition_map), do: schema.definitions

  def definitions(%Schema{} = schema, names, definition_map) do
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
        |> Enum.flat_map(fn
          %{type: type} -> [type]
          _variant -> []
        end)
        |> Enum.filter(&Map.has_key?(definition_map, &1))

      include_dependencies(names ++ dependencies, definition_map, MapSet.put(acc, name))
    end
  end
end
