defmodule KiwiCodec.Metadata do
  @moduledoc """
  Compiled metadata attached to generated Kiwi modules.

  Generated modules expose this metadata through `__kiwi_props__/0` so encoders,
  decoders, inspectors, and tooling can work from one normalized description of
  fields, enum values, and definition kind.
  """

  alias KiwiCodec.Metadata.Field

  @type kind :: :message | :struct | :enum

  @type t :: %__MODULE__{
          kind: kind(),
          ordered_fields: [Field.t()],
          fields_by_id: %{pos_integer() => Field.t()},
          fields_by_name: %{atom() => Field.t()},
          enum_by_name: %{atom() => integer()},
          enum_by_value: %{integer() => atom()}
        }

  defstruct kind: :message,
            ordered_fields: [],
            fields_by_id: %{},
            fields_by_name: %{},
            enum_by_name: %{},
            enum_by_value: %{}

  defmodule Field do
    @moduledoc """
    Compiled metadata for one field in a generated Kiwi module.
    """

    @type t :: %__MODULE__{
            id: pos_integer() | nil,
            name: atom() | nil,
            source_name: String.t() | nil,
            type: atom() | {:enum, module()} | module() | nil,
            repeated?: boolean(),
            deprecated?: boolean()
          }

    defstruct id: nil,
              name: nil,
              source_name: nil,
              type: nil,
              repeated?: false,
              deprecated?: false
  end
end
