defmodule KiwiCodec.DSL do
  @moduledoc """
  Compile-time DSL behind `use KiwiCodec`.

  The DSL records schema fields and enum values. `KiwiCodec.GeneratedModule.*`
  modules build the generated metadata, typespecs, structs, enum helpers, and
  inspect integration before compilation.
  """

  alias KiwiCodec.GeneratedModule

  defmacro field(name, id, options \\ []) do
    quote bind_quoted: [name: name, id: id, options: options] do
      unless is_atom(name), do: raise(ArgumentError, "expected field name to be an atom")

      unless is_integer(id) and id > 0,
        do: raise(ArgumentError, "expected field id to be positive")

      unless Keyword.keyword?(options),
        do: raise(ArgumentError, "expected field options keyword list")

      @kiwi_fields {name, id, options}
    end
  end

  defmacro enum_value(name, value) do
    quote bind_quoted: [name: name, value: value] do
      unless is_atom(name), do: raise(ArgumentError, "expected enum name to be an atom")
      unless is_integer(value), do: raise(ArgumentError, "expected enum value to be an integer")

      @kiwi_enum_values {name, value}
    end
  end

  defmacro __before_compile__(env) do
    kind = env.module |> Module.get_attribute(:kiwi_options) |> Keyword.fetch!(:kind)
    fields = env.module |> Module.get_attribute(:kiwi_fields) |> Enum.reverse()
    enum_values = env.module |> Module.get_attribute(:kiwi_enum_values) |> Enum.reverse()
    metadata = GeneratedModule.Metadata.build(kind, fields, enum_values)

    quote do
      @spec __kiwi_metadata__() :: KiwiCodec.Metadata.t()
      def __kiwi_metadata__, do: unquote(Macro.escape(metadata))

      def __kiwi_definition__,
        do: unquote(Macro.escape(%{kind: kind, fields: metadata.ordered_fields}))

      unquote(GeneratedModule.Shape.define(kind, fields, enum_values))
    end
  end
end
