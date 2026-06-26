defmodule KiwiCodec.Inspect do
  @moduledoc """
  Shared `Inspect` implementation for generated Kiwi structs.
  """

  import Inspect.Algebra

  alias KiwiCodec.Metadata

  def inspect(%module{} = value, opts) do
    metadata = module.__kiwi_props__()

    {fields, more?} =
      metadata.ordered_fields |> visible_fields(metadata, value) |> limit_fields(opts)

    concat([
      "#",
      inspect(module),
      "<",
      fields |> Enum.map(&field_doc(&1, value, opts)) |> Enum.intersperse(", ") |> concat(),
      maybe_more(more?),
      ">"
    ])
  end

  defp visible_fields(fields, %Metadata{kind: :struct}, _value), do: fields

  defp visible_fields(fields, %Metadata{kind: :message}, value) do
    Enum.filter(fields, fn field -> not is_nil(Map.get(value, field.name)) end)
  end

  defp limit_fields(fields, %{limit: :infinity}), do: {fields, false}

  defp limit_fields(fields, %{limit: limit}) when is_integer(limit) and limit >= 0 do
    limited = Enum.take(fields, limit)
    {limited, length(fields) > limit}
  end

  defp field_doc(field, value, opts) do
    concat([Atom.to_string(field.name), ": ", to_doc(Map.get(value, field.name), opts)])
  end

  defp maybe_more(true), do: "..."
  defp maybe_more(false), do: empty()
end
