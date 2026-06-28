defmodule KiwiCodec.MixProject do
  use Mix.Project

  @version "0.2.2"
  @source_url "https://github.com/open-pencil/kiwi_codec"

  def project do
    [
      app: :kiwi_codec,
      version: @version,
      elixir: "~> 1.19",
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      description: "Pure Elixir codec for Kiwi schema binary messages",
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix], flags: [:no_opaque]],
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp aliases do
    [
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test",
        "credo --strict",
        "dialyzer --plt",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ]
    ]
  end

  defp deps do
    [
      rustq_dep(),
      {:varint, "~> 1.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.6", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp rustq_dep do
    {:rustq, "~> 0.8.2", runtime: false}
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ["lib", "priv", "guides", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE*"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/rustler-generator-architecture.md"
      ],
      groups_for_modules: docs_groups_for_modules(),
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp docs_groups_for_modules do
    [
      Schema: [
        KiwiCodec.Metadata,
        KiwiCodec.Metadata.Field,
        KiwiCodec.Schema,
        KiwiCodec.Schema.Enum,
        KiwiCodec.Schema.EnumVariant,
        KiwiCodec.Schema.Field,
        KiwiCodec.Schema.Message,
        KiwiCodec.Schema.Struct
      ],
      "Wire encoding": [
        KiwiCodec.Wire,
        KiwiCodec.Wire.VarFloat,
        KiwiCodec.Wire.Varint
      ],
      Generation: [
        KiwiCodec.FileGenerator,
        KiwiCodec.ModuleCompiler,
        KiwiCodec.ModuleGenerator,
        KiwiCodec.RustlerGenerator
      ],
      "Implementation internals": [
        KiwiCodec.DSL,
        KiwiCodec.GeneratedModule.Metadata,
        KiwiCodec.GeneratedModule.Shape,
        KiwiCodec.GeneratedModule.TypeSpec,
        KiwiCodec.PrimitiveType,
        KiwiCodec.RustlerGenerator.DecoderMacro,
        KiwiCodec.RustlerGenerator.Definition,
        KiwiCodec.RustlerGenerator.Entrypoint,
        KiwiCodec.RustlerGenerator.Name,
        KiwiCodec.RustlerGenerator.Selection,
        KiwiCodec.RustlerGenerator.Splice,
        KiwiCodec.Schema.Binary,
        KiwiCodec.Schema.Binary.TypeIndex,
        KiwiCodec.Schema.Parser,
        KiwiCodec.Schema.Token,
        KiwiCodec.Schema.Tokenizer,
        KiwiCodec.Schema.Validator,
        KiwiCodec.SchemaInterpreter
      ]
    ]
  end
end
