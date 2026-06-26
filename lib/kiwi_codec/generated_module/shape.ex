defmodule KiwiCodec.GeneratedModule.Shape do
  @moduledoc """
  Emits enum, struct, and message shape code for modules generated with `use KiwiCodec`.
  """

  alias KiwiCodec.GeneratedModule.TypeSpec

  @spec define(KiwiCodec.Metadata.kind(), list(), list()) :: Macro.t()
  def define(:enum, _fields, enum_values) do
    enum_type = TypeSpec.enum_type(enum_values)

    quote do
      @type t() :: unquote(enum_type) | integer()

      def key(value), do: Map.get(__kiwi_metadata__().enum_by_value, value, value)
      def value(name), do: Map.fetch!(__kiwi_metadata__().enum_by_name, name)
    end
  end

  def define(_kind, fields, _enum_values) do
    struct_fields =
      Enum.map(fields, fn {name, _id, options} -> {name, Keyword.get(options, :default)} end)

    struct_type = TypeSpec.struct_type(fields)

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
end
