defmodule KiwiCodec.GeneratedModule.Metadata do
  @moduledoc """
  Builds compiled metadata for modules generated with `use KiwiCodec`.
  """

  alias KiwiCodec.Metadata
  alias KiwiCodec.Metadata.Field

  @spec build(Metadata.kind(), list(), list()) :: Metadata.t()
  def build(kind, fields, enum_values) do
    fields_metadata = Enum.map(fields, &field/1)

    %Metadata{
      kind: kind,
      ordered_fields: fields_metadata,
      fields_by_id: Map.new(fields_metadata, &{&1.id, &1}),
      fields_by_name: Map.new(fields_metadata, &{&1.name, &1}),
      enum_by_name: Map.new(enum_values),
      enum_by_value: Map.new(enum_values, fn {name, value} -> {value, name} end)
    }
  end

  defp field({name, id, options}) do
    %Field{
      id: id,
      name: name,
      source_name: Keyword.get(options, :source_name, Atom.to_string(name)),
      type: Keyword.fetch!(options, :type),
      repeated?: Keyword.get(options, :repeated, false),
      deprecated?: Keyword.get(options, :deprecated, false)
    }
  end
end
