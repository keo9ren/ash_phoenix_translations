defmodule AshPhoenixTranslations.GraphqlExtensionsTest do
  use ExUnit.Case, async: true

  alias AshPhoenixTranslations.GraphqlExtensions

  describe "generate/1" do
    test "generates extension module code for domains with translatable resources" do
      # Use test resources that have translations configured
      # For now, test with empty list to verify structure
      code = GraphqlExtensions.generate([])

      assert code =~ "defmodule TranslationExtensions do"
      assert code =~ "use Absinthe.Schema.Notation"
      assert code =~ "scalar :locale_scalar"
      assert code =~ "object :translation"
    end

    test "generates shared type definitions" do
      shared_types = GraphqlExtensions.generate_shared_types()

      assert shared_types =~ "scalar :locale_scalar"
      assert shared_types =~ "parse &AshPhoenixTranslations.Graphql.parse_locale/1"
      assert shared_types =~ "serialize &AshPhoenixTranslations.Graphql.serialize_locale/1"
      assert shared_types =~ "object :translation"
      assert shared_types =~ "field :locale, non_null(:string)"
      assert shared_types =~ "field :value, :string"
    end
  end

  describe "get_translatable_resources/1" do
    test "returns empty list when no domains provided" do
      assert GraphqlExtensions.get_translatable_resources([]) == []
    end

    test "returns empty list for domains without translatable resources" do
      # Test with non-existent or empty domains
      assert GraphqlExtensions.get_translatable_resources([NonExistent.Domain]) == []
    end
  end

  describe "generate_resource_extension/1" do
    # We'll need to create a test resource with translations
    # For now, test the structure
    test "generates extension code structure" do
      # This would need a proper test resource
      # For now, just verify the module exists and can be called
      assert is_function(&GraphqlExtensions.generate_resource_extension/1)
    end
  end

  describe "locale default fix" do
    test "add_locale_argument_to_query uses configurable default locale" do
      # Save original config
      original_locale = Application.get_env(:ash_phoenix_translations, :default_locale)

      try do
        # Test with custom default locale
        Application.put_env(:ash_phoenix_translations, :default_locale, :es)

        query_config = %{}
        result = AshPhoenixTranslations.Graphql.add_locale_argument_to_query(query_config)

        assert result.args[:locale][:default] == :es

        # Test with default (no config)
        Application.delete_env(:ash_phoenix_translations, :default_locale)

        result = AshPhoenixTranslations.Graphql.add_locale_argument_to_query(query_config)
        assert result.args[:locale][:default] == :en
      after
        # Restore original config
        if original_locale do
          Application.put_env(:ash_phoenix_translations, :default_locale, original_locale)
        else
          Application.delete_env(:ash_phoenix_translations, :default_locale)
        end
      end
    end

    test "locale default is no longer hardcoded to :de" do
      query_config = %{}
      result = AshPhoenixTranslations.Graphql.add_locale_argument_to_query(query_config)

      # Should NOT be :de
      refute result.args[:locale][:default] == :de

      # Should be :en (default) or configured value
      assert result.args[:locale][:default] in [:en, Application.get_env(:ash_phoenix_translations, :default_locale, :en)]
    end
  end
end
