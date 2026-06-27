defmodule KiwiCodec.RustlerGenerator.Name do
  @moduledoc """
  Naming helpers for Rustler decoder code generated from Kiwi schemas.
  """

  @spec decoder_function(String.t()) :: atom()
  def decoder_function(name) do
    name
    |> decoder_base()
    |> Kernel.<>("_from_decoder")
    |> RustQ.Atom.identifier!()
  end

  @spec message_fields_function(String.t()) :: atom()
  def message_fields_function(name) do
    name
    |> decoder_base()
    |> Kernel.<>("_fields_from_decoder")
    |> RustQ.Atom.identifier!()
  end

  @spec module_atom_static(String.t()) :: atom()
  def module_atom_static(name), do: static_name(name, "MODULE_ATOM")

  @spec struct_keys_static(String.t()) :: atom()
  def struct_keys_static(name), do: static_name(name, "STRUCT_KEYS")

  @spec static_alias(atom()) :: Macro.t()
  def static_alias(name), do: {:__aliases__, [], [name]}

  @spec module_name(String.t(), String.t()) :: String.t()
  def module_name(module_prefix, name), do: "Elixir.#{module_prefix}.#{name}"

  @spec field_name(String.t()) :: String.t()
  def field_name(name), do: Macro.underscore(name)

  @spec rust_identifier(String.t()) :: String.t()
  def rust_identifier(name) do
    name
    |> Macro.underscore()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  defp decoder_base(name), do: "decode_#{rust_identifier(name)}"

  defp static_name(name, suffix) do
    name
    |> rust_identifier()
    |> String.upcase()
    |> Kernel.<>("_#{suffix}")
    |> RustQ.Atom.identifier!()
  end
end
