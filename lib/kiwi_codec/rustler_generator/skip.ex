defmodule KiwiCodec.RustlerGenerator.Skip do
  @moduledoc """
  Generates generic Kiwi schema skip decoders for Rustler native backends.

  Skip decoders consume encoded values without allocating decoded Elixir terms.
  They are schema-generic and intended for callers that project only selected
  fields from a Kiwi payload.
  """

  alias KiwiCodec.RustlerGenerator.RustExpr
  alias KiwiCodec.Schema.Enum, as: SchemaEnum
  alias KiwiCodec.Schema.{Message, Struct}
  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.PatternBuilder, as: P
  alias RustQ.Rust.AST.Render

  defmodule Kind do
    @moduledoc """
    Semantic skip operation for one Kiwi field value.
    """

    @enforce_keys [:mode, :function]
    defstruct [:mode, :function]

    @type mode :: :one | :repeated | :bytes
    @type t :: %__MODULE__{mode: mode(), function: atom()}
  end

  @spec fragments([KiwiCodec.Schema.definition()], map()) :: [RustQ.Rust.Fragment.t()]
  def fragments(definitions, definition_map) do
    Enum.map(definitions, &definition(&1, definition_map))
  end

  @spec field_expr(map(), map()) :: String.t()
  def field_expr(field, definition_map) do
    field
    |> skip_call(definition_map)
    |> Render.render_expr()
    |> IO.iodata_to_binary()
  end

  @spec message_arm(map(), map()) :: RustQ.Rust.Fragment.t()
  def message_arm(field, definition_map) do
    arm = %AST.Arm{
      pattern: P.lit(field.id),
      body: [A.return_stmt(skip_call(field, definition_map))]
    }

    arm
    |> Render.render_arm()
    |> Rust.arm()
  end

  defp definition(%SchemaEnum{name: name}, _definition_map) do
    skip_function(name, [A.return_stmt(A.call(:kiwi_skip_uint_value, [:decoder]))])
  end

  defp definition(%Struct{name: name, fields: fields}, definition_map) do
    body = [
      A.return_stmt(
        A.call(:kiwi_skip_struct_fields, [
          A.var(:decoder),
          A.ref(A.array(skip_kinds(fields, definition_map)))
        ])
      )
    ]

    skip_function(name, body)
  end

  defp definition(%Message{name: name, fields: fields}, definition_map) do
    body = [
      A.return_stmt(
        A.call(:kiwi_skip_message_fields, [
          A.var(:decoder),
          A.lit(name),
          A.ref(A.array(skip_fields(fields, definition_map)))
        ])
      )
    ]

    skip_function(name, body)
  end

  defp skip_function(name, body) do
    Rust.ast_item(%AST.Function{
      name: RustQ.Atom.identifier!("skip_#{RustExpr.ident(name)}_from_decoder"),
      args: [A.arg(:decoder, "&mut Decoder<'_>")],
      returns: "NifResult<()>",
      body: body
    })
  end

  defp skip_fields(fields, definition_map) do
    Enum.map(fields, fn field ->
      A.struct([:KiwiSkipField], id: A.lit(field.id), kind: skip_kind_expr(field, definition_map))
    end)
  end

  defp skip_kinds(fields, definition_map),
    do: Enum.map(fields, &skip_kind_expr(&1, definition_map))

  defp skip_call(field, definition_map) do
    field
    |> skip_kind(definition_map)
    |> skip_kind_call()
  end

  defp skip_kind_expr(field, definition_map) do
    field
    |> skip_kind(definition_map)
    |> skip_kind_value()
  end

  defp skip_kind(%{array?: true, type: "byte"}, _definition_map),
    do: %Kind{mode: :bytes, function: :kiwi_skip_bytes_value}

  defp skip_kind(%{array?: true, type: type}, definition_map) do
    %Kind{mode: :repeated, function: scalar_skip_function(type, definition_map)}
  end

  defp skip_kind(%{type: type}, definition_map) do
    %Kind{mode: :one, function: scalar_skip_function(type, definition_map)}
  end

  defp skip_kind_call(%Kind{mode: :bytes}), do: A.try(A.call(:kiwi_skip_bytes_value, [:decoder]))

  defp skip_kind_call(%Kind{mode: :repeated, function: function}) do
    A.try(A.call(:kiwi_skip_repeated, [A.var(:decoder), A.path(function)]))
  end

  defp skip_kind_call(%Kind{mode: :one, function: function}) do
    A.try(A.call(function, [:decoder]))
  end

  defp skip_kind_value(%Kind{mode: :bytes}), do: A.path([:KiwiSkipKind, :Bytes])

  defp skip_kind_value(%Kind{mode: :repeated, function: function}) do
    A.path_call([:KiwiSkipKind, :Repeated], [A.path(function)])
  end

  defp skip_kind_value(%Kind{mode: :one, function: function}) do
    A.path_call([:KiwiSkipKind, :One], [A.path(function)])
  end

  defp scalar_skip_function(type, definition_map) do
    cond do
      KiwiCodec.PrimitiveType.name?(type) ->
        RustQ.Atom.identifier!("kiwi_skip_#{RustExpr.ident(type)}_value")

      Map.has_key?(definition_map, type) ->
        RustQ.Atom.identifier!("skip_#{RustExpr.ident(type)}_from_decoder")
    end
  end
end
