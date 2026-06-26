defmodule KiwiCodec.GeneratedModule.TypeSpec do
  @moduledoc """
  Builds typespec AST for generated Kiwi modules.
  """

  @spec struct_type(list()) :: Macro.t()
  def struct_type(fields) do
    {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], Enum.map(fields, &field/1)}]}
  end

  @spec enum_type([{atom(), integer()}]) :: Macro.t()
  def enum_type(enum_values) do
    enum_values
    |> Enum.map(&elem(&1, 0))
    |> enum_union()
  end

  defp field({name, _id, options}) do
    {name, nullable(Keyword.fetch!(options, :type), Keyword.get(options, :repeated, false))}
  end

  defp nullable(:byte, true), do: quote(do: binary() | nil)
  defp nullable(type, true), do: quote(do: [unquote(type(type))] | nil)
  defp nullable(type, false), do: quote(do: unquote(type(type)) | nil)

  defp type(:bool), do: quote(do: boolean())
  defp type(:byte), do: quote(do: 0..255)
  defp type(:float), do: quote(do: float())
  defp type(:int), do: quote(do: integer())
  defp type(:int64), do: quote(do: integer())
  defp type(:string), do: quote(do: String.t())
  defp type(:uint), do: quote(do: non_neg_integer())
  defp type(:uint64), do: quote(do: non_neg_integer())
  defp type({:enum, module}), do: quote(do: unquote(module).t())
  defp type(module) when is_atom(module), do: quote(do: unquote(module).t())

  defp enum_union([]), do: quote(do: atom())
  defp enum_union([value]), do: value

  defp enum_union([value | values]) do
    Enum.reduce(values, value, fn next, acc -> {:|, [], [acc, next]} end)
  end
end
