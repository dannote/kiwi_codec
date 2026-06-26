defmodule KiwiCodec.ModuleGenerator do
  @moduledoc """
  Generates Elixir source modules from parsed Kiwi schemas.
  """

  alias KiwiCodec.Schema
  alias KiwiCodec.Schema.Definition

  @spec generate(Schema.t(), keyword()) :: [{Path.t(), String.t()}]
  def generate(%Schema{} = schema, opts) do
    module_prefix = Keyword.fetch!(opts, :module_prefix)
    base_path = Keyword.get(opts, :base_path, "lib")

    Enum.map(schema.definitions, fn definition ->
      module = module_name(module_prefix, definition.name)
      path = Path.join(base_path, Macro.underscore(module) <> ".ex")
      {path, generate_module(schema, definition, module_prefix, module)}
    end)
  end

  defp generate_module(schema, %Definition{} = definition, prefix, module) do
    definition
    |> module_ast(schema, prefix, module)
    |> format_ast()
  end

  defp module_ast(%Definition{kind: :enum} = definition, _schema, _prefix, module) do
    values = Enum.map(definition.fields, &enum_value_ast/1)
    moduledoc = generated_moduledoc(definition)

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(moduledoc)

        use KiwiCodec, kind: :enum

        unquote_splicing(values)
      end
    end
  end

  defp module_ast(%Definition{} = definition, schema, prefix, module) do
    fields = Enum.map(definition.fields, &field_ast(schema, &1, prefix))
    moduledoc = generated_moduledoc(definition)

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(moduledoc)

        use KiwiCodec, kind: unquote(definition.kind)

        unquote_splicing(fields)
      end
    end
  end

  defp generated_moduledoc(%Definition{name: name, kind: kind}) do
    "Generated Kiwi #{kind} module for `#{name}`."
  end

  defp enum_value_ast(field) do
    name = field_name_ast(field.name)

    quote do
      enum_value(unquote(name), unquote(field.value))
    end
  end

  defp field_ast(schema, field, prefix) do
    name = field_name_ast(field.name)
    opts = field_options(schema, field, prefix)

    quote do
      field(unquote(name), unquote(field.value), unquote(Macro.escape(opts)))
    end
  end

  defp field_options(schema, field, prefix) do
    [type: field_type(schema, field.type, prefix), source_name: field.name]
    |> maybe_put(:repeated, field.array?)
    |> maybe_put(:deprecated, field.deprecated?)
  end

  defp field_type(schema, type, prefix) do
    if KiwiCodec.PrimitiveType.name?(type) do
      KiwiCodec.PrimitiveType.to_atom!(type)
    else
      schema_type(schema, type, prefix)
    end
  end

  defp schema_type(schema, type, prefix) do
    case Schema.definition(schema, type) do
      %Definition{kind: :enum} -> {:enum, Module.concat([prefix, type])}
      %Definition{} -> Module.concat([prefix, type])
      nil -> raise ArgumentError, "unknown type #{inspect(type)}"
    end
  end

  defp maybe_put(opts, _key, false), do: opts
  defp maybe_put(opts, key, true), do: Keyword.put(opts, key, true)

  defp module_name(prefix, name), do: Module.concat([prefix, name])

  defp field_name_ast(name) do
    name
    |> Macro.underscore()
    |> then(&Code.string_to_quoted!(":#{&1}"))
  end

  defp format_ast(ast) do
    ast
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end
end
