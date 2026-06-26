defmodule KiwiCodec.DSL do
  @moduledoc """
  Compile-time DSL behind `use KiwiCodec`.

  The DSL records schema fields and enum values, then emits struct, enum,
  metadata, type, encode/decode, and inspect helpers before compilation.
  """

  alias KiwiCodec.Metadata
  alias KiwiCodec.Metadata.Field

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
    fields = Module.get_attribute(env.module, :kiwi_fields) |> Enum.reverse()
    enum_values = Module.get_attribute(env.module, :kiwi_enum_values) |> Enum.reverse()
    metadata = build_metadata(kind, fields, enum_values)

    struct_fields =
      Enum.map(fields, fn {name, _id, options} -> {name, Keyword.get(options, :default)} end)

    type_fields = Enum.map(fields, &type_field/1)

    quote do
      @spec __kiwi_props__() :: KiwiCodec.Metadata.t()
      def __kiwi_props__, do: unquote(Macro.escape(metadata))

      def __kiwi_definition__,
        do: unquote(Macro.escape(%{kind: kind, fields: metadata.ordered_fields}))

      unquote(define_shape(kind, struct_fields, enum_values, type_fields))
    end
  end

  defp build_metadata(kind, fields, enum_values) do
    fields_metadata =
      Enum.map(fields, fn {name, id, options} ->
        %Field{
          id: id,
          name: name,
          source_name: Keyword.get(options, :source_name, Atom.to_string(name)),
          type: Keyword.fetch!(options, :type),
          repeated?: Keyword.get(options, :repeated, false),
          deprecated?: Keyword.get(options, :deprecated, false)
        }
      end)

    %Metadata{
      kind: kind,
      ordered_fields: fields_metadata,
      fields_by_id: Map.new(fields_metadata, &{&1.id, &1}),
      fields_by_name: Map.new(fields_metadata, &{&1.name, &1}),
      enum_by_name: Map.new(enum_values),
      enum_by_value: Map.new(enum_values, fn {name, value} -> {value, name} end)
    }
  end

  defp define_shape(:enum, _struct_fields, enum_values, _type_fields) do
    enum_type = enum_values |> Enum.map(&elem(&1, 0)) |> enum_typespec()

    quote do
      @type t() :: unquote(enum_type) | integer()

      def key(value), do: Map.get(__kiwi_props__().enum_by_value, value, value)
      def value(name), do: Map.fetch!(__kiwi_props__().enum_by_name, name)
    end
  end

  defp define_shape(_kind, struct_fields, _enum_values, type_fields) do
    struct_type = struct_type_ast(type_fields)

    quote do
      defstruct unquote(Macro.escape(struct_fields))
      @type t() :: unquote(struct_type)

      def encode(%__MODULE__{} = struct), do: KiwiCodec.encode(struct)
      def decode(binary), do: KiwiCodec.decode(binary, __MODULE__)

      defimpl Inspect do
        def inspect(value, opts), do: KiwiCodec.Inspect.inspect(value, opts)
      end
    end
  end

  defp type_field({name, _id, options}) do
    {name,
     nullable_type_ast(Keyword.fetch!(options, :type), Keyword.get(options, :repeated, false))}
  end

  defp struct_type_ast(type_fields) do
    {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], type_fields}]}
  end

  defp nullable_type_ast(:byte, true), do: quote(do: binary() | nil)
  defp nullable_type_ast(type, true), do: quote(do: [unquote(type_ast(type))] | nil)
  defp nullable_type_ast(type, false), do: quote(do: unquote(type_ast(type)) | nil)

  defp type_ast(:bool), do: quote(do: boolean())
  defp type_ast(:byte), do: quote(do: 0..255)
  defp type_ast(:float), do: quote(do: float())
  defp type_ast(:int), do: quote(do: integer())
  defp type_ast(:int64), do: quote(do: integer())
  defp type_ast(:string), do: quote(do: String.t())
  defp type_ast(:uint), do: quote(do: non_neg_integer())
  defp type_ast(:uint64), do: quote(do: non_neg_integer())
  defp type_ast({:enum, module}), do: quote(do: unquote(module).t())
  defp type_ast(module) when is_atom(module), do: quote(do: unquote(module).t())

  defp enum_typespec([]), do: quote(do: atom())
  defp enum_typespec([value]), do: value

  defp enum_typespec([value | values]) do
    Enum.reduce(values, value, fn next, acc -> {:|, [], [acc, next]} end)
  end
end
