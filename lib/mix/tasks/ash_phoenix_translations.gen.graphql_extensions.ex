defmodule Mix.Tasks.AshPhoenixTranslations.Gen.GraphqlExtensions do
  @moduledoc """
  Generates an Absinthe schema extension module for translatable Ash resources.

  This task introspects your Ash domains to find resources with translations
  and generates an Absinthe schema extension module that adds translation fields
  to your GraphQL schema.

  ## Usage

      mix ash_phoenix_translations.gen.graphql_extensions

  Or specify domains explicitly:

      mix ash_phoenix_translations.gen.graphql_extensions --domains MyApp.Catalog,MyApp.Shop

  Or specify output file:

      mix ash_phoenix_translations.gen.graphql_extensions --output lib/my_app_web/schema/translation_extensions.ex

  ## Options

    * `--domains` - Comma-separated list of domain modules to introspect (optional)
    * `--output` - Output file path (default: lib/APP_NAME_web/schema/translation_extensions.ex)
    * `--module` - Module name for the extension (default: APPNAMEWeb.Schema.TranslationExtensions)

  ## What It Does

  1. Scans your Ash domains for resources with `graphql_translations true`
  2. Generates an extension module with `extend object` blocks
  3. Adds translation fields for each translatable attribute
  4. Provides instructions for importing into your Absinthe schema

  ## Example Output

  The generated module will look like:

      defmodule MyAppWeb.Schema.TranslationExtensions do
        use Absinthe.Schema.Notation

        extend object(:product) do
          field :name_translation, :string do
            arg :locale, non_null(:locale_scalar)
            resolve &AshPhoenixTranslations.Graphql.resolve_translation/3
          end

          field :name_translations, list_of(:translation) do
            resolve &AshPhoenixTranslations.Graphql.resolve_all_translations/3
          end
        end

        scalar :locale_scalar do
          parse &AshPhoenixTranslations.Graphql.parse_locale/1
          serialize &AshPhoenixTranslations.Graphql.serialize_locale/1
        end

        object :translation do
          field :locale, non_null(:string)
          field :value, :string
        end
      end

  ## Next Steps

  After running this task, add to your Absinthe schema:

      defmodule MyAppWeb.Schema do
        use Absinthe.Schema
        use AshGraphql, domains: [MyApp.Catalog]

        import_type_extensions MyAppWeb.Schema.TranslationExtensions

        query do
          # your queries
        end
      end

  """

  use Mix.Task

  alias AshPhoenixTranslations.GraphqlExtensions

  @shortdoc "Generates GraphQL schema extensions for translatable resources"

  @impl Mix.Task
  def run(args) do
    # Parse options
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          domains: :string,
          output: :string,
          module: :string
        ]
      )

    Mix.Task.run("compile")

    # Get domains
    domains = get_domains(opts)

    if Enum.empty?(domains) do
      Mix.shell().error("""
      No domains found. Please specify domains using --domains option:

          mix ash_phoenix_translations.gen.graphql_extensions --domains MyApp.Catalog,MyApp.Shop

      Or ensure your domains are defined and compiled.
      """)

      exit({:shutdown, 1})
    end

    # Get translatable resources
    resources = GraphqlExtensions.get_translatable_resources(domains)

    if Enum.empty?(resources) do
      Mix.shell().info("""
      No translatable resources found with GraphQL support.

      Searched domains: #{inspect(domains)}

      Make sure your resources have:
      1. AshPhoenixTranslations extension
      2. AshGraphql.Resource extension
      3. At least one translatable_attribute defined
      """)

      exit({:shutdown, 0})
    end

    # Determine output path and module name
    {output_path, module_name} = get_output_config(opts)

    # Generate extension code
    code = generate_extension_code(module_name, resources)

    # Ensure directory exists
    output_path |> Path.dirname() |> File.mkdir_p!()

    # Write file
    File.write!(output_path, code)

    Mix.shell().info("""
    #{IO.ANSI.green()}✓ Generated GraphQL extension module!#{IO.ANSI.reset()}

    File: #{output_path}
    Module: #{module_name}
    Resources: #{length(resources)}

    #{list_resources(resources)}

    #{IO.ANSI.yellow()}Next steps:#{IO.ANSI.reset()}

    1. Import the extension in your Absinthe schema:

        defmodule YourApp.Schema do
          use Absinthe.Schema
          use AshGraphql, domains: #{inspect(domains)}

          import_type_extensions #{module_name}

          query do
            # your queries
          end
        end

    2. Query translations in GraphQL:

        query {
          listProducts {
            id
            nameTranslation(locale: "es")
            nameTranslations {
              locale
              value
            }
          }
        }

    """)
  end

  defp get_domains(opts) do
    case opts[:domains] do
      nil ->
        # Try to auto-discover domains from config or compiled modules
        discover_domains()

      domains_string ->
        domains_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&Module.concat([&1]))
    end
  end

  defp discover_domains do
    # Try to find domains from loaded modules
    :application.get_key(:ash_phoenix_translations, :modules)
    |> case do
      {:ok, _modules} ->
        # Look for modules that might be domains
        # This is a simple heuristic - in production, users should specify domains
        []

      _ ->
        []
    end
  end

  defp get_output_config(opts) do
    app_name = Mix.Project.config()[:app]
    app_module = app_name |> to_string() |> Macro.camelize()

    default_module = Module.concat([app_module <> "Web", "Schema", "TranslationExtensions"])
    default_path = "lib/#{app_name}_web/schema/translation_extensions.ex"

    module_name = opts[:module] && Module.concat([opts[:module]]) || default_module
    output_path = opts[:output] || default_path

    {output_path, module_name}
  end

  defp generate_extension_code(module_name, resources) do
    extensions =
      resources
      |> Enum.map(&GraphqlExtensions.generate_resource_extension/1)
      |> Enum.join("\n")

    """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Auto-generated GraphQL schema extensions for translatable resources.

      Generated by: mix ash_phoenix_translations.gen.graphql_extensions
      Generated at: #{DateTime.utc_now() |> DateTime.to_string()}

      To use this module, import it in your Absinthe schema:

          defmodule MyApp.Schema do
            use Absinthe.Schema
            import_type_extensions #{inspect(module_name)}
          end

      Resources with translation support:
      #{resources |> Enum.map(&("  - " <> inspect(&1))) |> Enum.join("\n")}
      \"\"\"

      use Absinthe.Schema.Notation

    #{GraphqlExtensions.generate_shared_types()}

    #{extensions}
    end
    """
  end

  defp list_resources(resources) do
    resources
    |> Enum.with_index(1)
    |> Enum.map(fn {resource, index} ->
      attrs = AshPhoenixTranslations.Info.translatable_attributes(resource)
      attr_names = Enum.map(attrs, & &1.name)
      "  #{index}. #{inspect(resource)} - Fields: #{inspect(attr_names)}"
    end)
    |> Enum.join("\n")
  end
end
