defmodule KiwiCodec.Schema do
  @moduledoc """
  Parsed Kiwi schema.
  """

  alias KiwiCodec.Schema.Definition

  @type t :: %__MODULE__{package: String.t() | nil, definitions: [Definition.t()]}

  defstruct package: nil, definitions: []

  @spec native_type?(String.t()) :: boolean()
  def native_type?(type), do: KiwiCodec.PrimitiveType.name?(type)

  @spec definition(t(), String.t()) :: Definition.t() | nil
  def definition(%__MODULE__{definitions: definitions}, name) do
    Enum.find(definitions, &(&1.name == name))
  end
end

defmodule KiwiCodec.Schema.Definition do
  @moduledoc """
  Kiwi enum, struct, or message definition.
  """

  alias KiwiCodec.Schema.Field

  @type kind :: :enum | :struct | :message
  @type t :: %__MODULE__{
          name: String.t(),
          kind: kind(),
          fields: [Field.t()],
          line: non_neg_integer(),
          column: non_neg_integer()
        }

  defstruct name: nil,
            kind: nil,
            fields: [],
            line: 0,
            column: 0
end

defmodule KiwiCodec.Schema.Field do
  @moduledoc """
  Kiwi schema field or enum member.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t() | nil,
          array?: boolean(),
          deprecated?: boolean(),
          value: integer(),
          line: non_neg_integer(),
          column: non_neg_integer()
        }

  defstruct name: nil,
            type: nil,
            array?: false,
            deprecated?: false,
            value: nil,
            line: 0,
            column: 0
end
