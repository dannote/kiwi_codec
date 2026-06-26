defmodule KiwiCodec.Schema.Validator do
  @moduledoc """
  Validates parsed Kiwi schemas after grammar parsing.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}

  @reserved_names ~w(ByteBuffer package)

  @spec validate!(Schema.t()) :: Schema.t()
  def validate!(%Schema{} = schema) do
    defined = Enum.map(schema.definitions, & &1.name)
    duplicates = defined -- Enum.uniq(defined)

    cond do
      duplicates != [] ->
        raise ArgumentError, "duplicate definition #{inspect(hd(duplicates))}"

      Enum.any?(defined, &(&1 in @reserved_names)) ->
        raise ArgumentError, "reserved definition name"

      true ->
        validate_definitions!(schema, defined)
    end
  end

  defp validate_definitions!(schema, defined) do
    Enum.each(schema.definitions, fn definition ->
      validate_member_names!(definition)
      validate_member_ids!(definition)
      validate_field_types!(definition, defined)
    end)

    schema
  end

  defp validate_member_names!(%SchemaEnum{} = definition) do
    names = Enum.map(definition.variants, & &1.name)

    if names != Enum.uniq(names) do
      raise ArgumentError, "duplicate variant name in #{definition.name}"
    end
  end

  defp validate_member_names!(definition) do
    names = Enum.map(definition.fields, & &1.name)

    if names != Enum.uniq(names) do
      raise ArgumentError, "duplicate field name in #{definition.name}"
    end
  end

  defp validate_member_ids!(%Struct{}), do: :ok

  defp validate_member_ids!(%SchemaEnum{} = definition) do
    values = Enum.map(definition.variants, & &1.value)

    if values != Enum.uniq(values) do
      raise ArgumentError, "duplicate enum value in #{definition.name}"
    end
  end

  defp validate_member_ids!(%Message{} = definition) do
    ids = Enum.map(definition.fields, & &1.id)

    if ids != Enum.uniq(ids) do
      raise ArgumentError, "duplicate field id in #{definition.name}"
    end
  end

  defp validate_field_types!(%SchemaEnum{}, _defined), do: :ok

  defp validate_field_types!(definition, defined) do
    Enum.each(definition.fields, fn field ->
      unless Schema.native_type?(field.type) or field.type in defined do
        raise ArgumentError,
              "unknown type #{inspect(field.type)} for #{definition.name}.#{field.name}"
      end
    end)
  end
end
