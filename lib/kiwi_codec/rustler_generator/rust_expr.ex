defmodule KiwiCodec.RustlerGenerator.RustExpr do
  @moduledoc """
  Shared Rust source-expression helpers for Kiwi Rustler generator modules.

  These helpers keep schema-generic renderer modules focused on decoder shape
  while centralizing primitive decoder expressions and small formatting details.
  """

  @spec primitive(KiwiCodec.PrimitiveType.name()) :: String.t() | nil
  def primitive(type) do
    if KiwiCodec.PrimitiveType.name?(type) do
      type
      |> primitive_decoder()
      |> decoder_call_source()
    end
  end

  @spec ident(String.t() | atom()) :: String.t()
  def ident(name) when is_atom(name), do: Atom.to_string(name)

  def ident(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  @spec indent(iodata(), non_neg_integer()) :: String.t() | []
  def indent([], _spaces), do: []

  def indent(iodata, spaces) do
    padding = String.duplicate(" ", spaces)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end

  defp primitive_decoder("bool"), do: {:read_bool, []}
  defp primitive_decoder("byte"), do: {:read_byte, []}
  defp primitive_decoder("string"), do: {:read_string, [:env]}
  defp primitive_decoder("float"), do: {:read_var_float, [:env]}
  defp primitive_decoder("int"), do: {:read_var_int, []}
  defp primitive_decoder("int64"), do: {:read_var_int64, []}
  defp primitive_decoder("uint"), do: {:read_var_uint, []}
  defp primitive_decoder("uint64"), do: {:read_var_uint64, []}

  defp decoder_call_source({method, args}) do
    ["decoder.", Atom.to_string(method), "(", args_source(args), ")?"]
    |> IO.iodata_to_binary()
  end

  defp args_source(args), do: Enum.map_join(args, ", ", &Atom.to_string/1)
end
