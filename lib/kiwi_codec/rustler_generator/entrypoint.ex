defmodule KiwiCodec.RustlerGenerator.Entrypoint do
  @moduledoc """
  Generates Rustler NIF entrypoint items for Kiwi decoders.
  """

  alias KiwiCodec.RustlerGenerator.Name
  alias RustQ.Meta.AST, as: MetaAST

  @type entrypoint :: {atom() | String.t(), String.t()}

  @spec fragments([entrypoint()]) :: [RustQ.Rust.Fragment.t()]
  def fragments(entrypoints), do: Enum.map(entrypoints, &item/1)

  defp item({nif_name, definition_name}) do
    module = generated_module!(nif_name, definition_name)
    MetaAST.item(module, RustQ.Atom.identifier!(to_string(nif_name)))
  end

  defp generated_module!(nif_name, definition_name) do
    nif_name = RustQ.Atom.identifier!(to_string(nif_name))
    decoder_name = Name.decoder_function(definition_name)

    module =
      Module.concat([
        KiwiCodec.RustlerGenerator.Generated,
        "Entrypoint#{nif_name}#{:erlang.phash2(definition_name)}"
      ])

    if Code.ensure_loaded?(module) do
      module
    else
      Module.create(
        module,
        quote do
          use RustQ.Meta
          alias RustQ.Type, as: R
          import KiwiCodec.RustlerGenerator.DecoderMacro, only: [entrypoint: 2]

          entrypoint(unquote(nif_name), unquote(decoder_name))
        end,
        Macro.Env.location(__ENV__)
      )

      module
    end
  end
end
