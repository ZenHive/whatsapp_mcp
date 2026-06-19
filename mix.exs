defmodule WhatsappMcp.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/ZenHive/whatsapp_mcp"

  def project do
    [
      app: :whatsapp_mcp,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      aliases: aliases(),
      cli: cli(),

      # Hex
      description: "MCP server for WhatsApp with full read/write access via Go bridge",
      package: package(),
      source_url: @source_url,

      # Docs
      name: "WhatsappMcp",
      docs: docs(),

      # Test coverage - run with: mix test --cover
      test_coverage: [summary: [threshold: 80]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WhatsappMcp.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp escript do
    [main_module: WhatsappMcp.CLI]
  end

  defp deps do
    [
      {:exqlite, "== 0.37.0"},
      {:jason, "== 1.4.5"},
      {:req, "== 0.6.1"},
      {:plug, "== 1.19.2", only: [:dev, :test]},

      # Dev/test
      {:ex_unit_json, "== 0.5.0", only: [:dev, :test], runtime: false},
      {:tidewave, "== 0.6.0", only: :dev},
      {:bandit, "== 1.12.0", only: :dev},
      {:ex_doc, "== 0.40.3", only: :dev, runtime: false},
      {:styler, "== 1.11.0", only: [:dev, :test], runtime: false},
      {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
      {:sobelow, "== 0.14.1", only: [:dev, :test], runtime: false},
      {:doctor, "== 0.23.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "== 1.4.7", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "== 0.2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["ZenHive"],
      # Include Go bridge source - users need Go 1.21+ to build
      # Exclude bridge/store/ (databases and downloaded media)
      files:
        ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md) ++
          ~w(bridge/main.go bridge/go.mod bridge/go.sum)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      formatters: ["html"],
      groups_for_modules: [
        Core: [
          WhatsappMcp,
          WhatsappMcp.Application,
          WhatsappMcp.Server,
          WhatsappMcp.CLI
        ],
        "MCP Tools": [
          WhatsappMcp.Tools,
          WhatsappMcp.Tools.Definitions,
          WhatsappMcp.Tools.Handlers,
          WhatsappMcp.Tools.Formatters
        ],
        Database: [
          WhatsappMcp.Database,
          WhatsappMcp.Database.Chats,
          WhatsappMcp.Database.Messages,
          WhatsappMcp.Database.Contacts,
          WhatsappMcp.Database.Helpers
        ],
        Bridge: [
          WhatsappMcp.Bridge,
          WhatsappMcp.Config
        ]
      ]
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4019) end)'"
      ]
    ]
  end

  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
  end
end
