defmodule AshPhoenixTranslations.Calculations.DatabaseTranslation do
  @moduledoc """
  Calculation for fetching translations from database storage.

  Returns the translation for the current locale, with fallback support.
  """

  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def has_expression?() do
    # Always return false to ensure calculate/3 is used for cross-data-layer compatibility
    # expression/2 is available but only used internally when appropriate
    false
  end

  @impl true
  def load(_query, opts, _context) do
    # Tell Ash to load the storage field before running the calculation
    attribute_name = Keyword.fetch!(opts, :attribute_name)
    storage_field = :"#{attribute_name}_translations"
    [storage_field]
  end

  @impl true
  def calculate(records, opts, context) do
    attribute_name = Keyword.fetch!(opts, :attribute_name)
    fallback = Keyword.get(opts, :fallback)

    # Get the current locale from context
    locale = get_locale(context)

    # Get translations for each record
    Enum.map(records, fn record ->
      storage_field = :"#{attribute_name}_translations"
      translations = Map.get(record, storage_field, %{})

      # Use the fallback module for robust translation fetching
      AshPhoenixTranslations.Fallback.get_translation(
        translations,
        locale,
        fallback: fallback,
        default: nil
      )
    end)
  end

  @impl true
  def expression(opts, context) do
    # NOTE: This callback is currently disabled via has_expression?/0 returning false
    # for cross-data-layer compatibility. The calculate/3 callback handles all data layers correctly.
    #
    # This implementation demonstrates how PostgreSQL-specific optimization could work
    # using JSONB operators for filtering/sorting, but is not currently used.
    # Future enhancement: Enable this when ref() in fragments is properly tested
    # with both ETS and PostgreSQL data layers.

    # Get resource from opts (passed by transformer)
    resource = Keyword.get(opts, :resource)

    # Only provide SQL expression for PostgreSQL data layer
    # For other data layers (e.g., ETS), return nil to use calculate/3 callback
    case resource && Ash.DataLayer.data_layer(resource) do
      AshPostgres.DataLayer ->
        attribute_name = Keyword.fetch!(opts, :attribute_name)
        storage_field = :"#{attribute_name}_translations"
        locale = get_locale(context)

        require Ash.Expr

        # Return an expression that extracts the current locale's translation from JSONB
        # This makes the calculation filterable and sortable in PostgreSQL
        Ash.Expr.expr(fragment("? ->> ?", ^ref(storage_field), ^to_string(locale)))

      _ ->
        # For non-SQL data layers, return nil to use calculate/3 callback
        # This ensures compatibility with ETS and other data layers
        nil
    end
  end

  defp get_locale(context) when is_map(context) do
    # Handle different context types
    locale =
      case context do
        %{locale: locale} -> locale
        %{source_context: %{locale: locale}} -> locale
        _ -> nil
      end

    locale ||
      Process.get(:locale) ||
      Application.get_env(:ash_phoenix_translations, :default_locale, :en)
  end
end
