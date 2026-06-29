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

  @spec fragments([KiwiCodec.Schema.definition()], map(), keyword()) :: [RustQ.Rust.Fragment.t()]
  def fragments(definitions, definition_map, opts \\ []) do
    messages? = Keyword.get(opts, :messages?, true)
    struct_mode = Keyword.get(opts, :struct_mode, :match)
    Enum.map(definitions, &definition(&1, definition_map, messages?, struct_mode))
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

  defp definition(definition, definition_map, messages?, struct_mode)
  defp definition(%SchemaEnum{}, _definition_map, _messages?, _struct_mode), do: []

  defp definition(%Struct{name: name, fields: fields}, definition_map, _messages?, :match) do
    Rust.item([
      "kiwi_skip_struct_decoder! {\n",
      "    fn ",
      skip_function_name(name),
      ";\n",
      "    decoder decoder;\n",
      "    fields [\n",
      RustExpr.indent(field_kinds(fields, definition_map), 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp definition(%Struct{name: name, fields: fields}, definition_map, _messages?, :descriptor) do
    Rust.item([
      "kiwi_skip_struct_decoder! {\n",
      "    fn ",
      skip_function_name(name),
      ";\n",
      "    decoder decoder;\n",
      "    fields [\n",
      RustExpr.indent(struct_descriptor_field_kinds(fields, definition_map), 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp definition(%Message{}, _definition_map, false, _struct_mode), do: []

  defp definition(%Message{name: name, fields: fields}, definition_map, true, _struct_mode) do
    Rust.item([
      "kiwi_skip_message_decoder! {\n",
      "    fn ",
      skip_function_name(name),
      ";\n",
      "    decoder decoder;\n",
      "    definition ",
      inspect(name),
      ";\n",
      "    fields [\n",
      RustExpr.indent(field_entries(fields, definition_map), 8),
      "\n    ]\n",
      "}"
    ])
  end

  defp field_entries(fields, definition_map) do
    fields
    |> Enum.map(fn field ->
      [Integer.to_string(field.id), " => ", field_kind(field, definition_map), ";"]
    end)
    |> Enum.intersperse("\n")
  end

  defp field_kinds(fields, definition_map) do
    fields
    |> Enum.map(&[field_kind(&1, definition_map), ";"])
    |> Enum.intersperse("\n")
  end

  defp struct_descriptor_field_kinds(fields, definition_map) do
    fields
    |> Enum.map(&[struct_descriptor_field_kind(&1, definition_map), ";"])
    |> Enum.intersperse("\n")
  end

  defp skip_call(field, definition_map) do
    field
    |> skip_kind(definition_map)
    |> skip_kind_call()
  end

  def field_kind(field, definition_map) do
    field
    |> skip_kind(definition_map)
    |> skip_kind_tokens()
  end

  defp skip_function_name(name), do: ["skip_", RustExpr.ident(name), "_from_decoder"]

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

  defp skip_kind_tokens(%Kind{mode: :bytes}), do: "bytes kiwi_skip_bytes_value"

  defp skip_kind_tokens(%Kind{mode: mode, function: function}),
    do: [Atom.to_string(mode), " ", Atom.to_string(function)]

  defp struct_descriptor_field_kind(field, definition_map) do
    kind = skip_kind(field, definition_map)
    [repeated_literal(kind), " ", bytes_literal(kind), " ", Atom.to_string(kind.function)]
  end

  defp repeated_literal(%Kind{mode: :repeated}), do: "true"
  defp repeated_literal(%Kind{}), do: "false"

  defp bytes_literal(%Kind{mode: :bytes}), do: "true"
  defp bytes_literal(%Kind{}), do: "false"

  defp scalar_skip_function(type, definition_map) do
    cond do
      KiwiCodec.PrimitiveType.name?(type) ->
        RustQ.Atom.identifier!("kiwi_skip_#{RustExpr.ident(type)}_value")

      match?(%SchemaEnum{}, Map.get(definition_map, type)) ->
        :kiwi_skip_uint_value

      Map.has_key?(definition_map, type) ->
        RustQ.Atom.identifier!("skip_#{RustExpr.ident(type)}_from_decoder")
    end
  end
end
