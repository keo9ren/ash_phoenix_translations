defmodule AshPhoenixTranslations.JsonApiLocaleIntegrationTest do
  use ExUnit.Case, async: true

  alias AshPhoenixTranslations.JsonApi
  alias AshPhoenixTranslations.JsonApi.LocalePlug

  import Plug.Conn
  import Plug.Test

  # Test domain and resource
  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshPhoenixTranslations.JsonApiLocaleIntegrationTest.TestResource
    end
  end

  defmodule TestResource do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshPhoenixTranslations],
      validate_domain_inclusion?: false

    attributes do
      uuid_primary_key :id

      attribute :price, :decimal, public?: true
      attribute :sku, :string, public?: true
    end

    translations do
      translatable_attribute :name, :string do
        locales [:en, :es, :fr]
      end

      translatable_attribute :description, :text do
        locales [:en, :es, :fr]
      end

      backend :database
    end

    actions do
      defaults [:read, :update, :destroy]

      create :create do
        primary? true
        accept [:name_translations, :description_translations, :price, :sku]
      end
    end
  end

  describe "LocalePlug - Query Parameter Extraction" do
    test "extracts locale from query parameter" do
      conn =
        :get
        |> conn("/?locale=es")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :es
      assert conn.private[:ash_json_api_locale] == :es
    end

    test "validates locale parameter against whitelist" do
      # Valid locale
      conn =
        :get
        |> conn("/?locale=en")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :en

      # Invalid locale should fall back to default
      conn =
        :get
        |> conn("/?locale=invalid")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :en
    end

    test "handles multiple query parameters" do
      conn =
        :get
        |> conn("/?locale=fr&filter=active")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :fr
    end
  end

  describe "LocalePlug - Accept-Language Header Parsing" do
    test "parses Accept-Language header with single locale" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "es")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :es
    end

    test "parses Accept-Language header with quality values" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "es-ES,es;q=0.9,en;q=0.8")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :es
    end

    test "selects highest quality supported locale" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "de;q=0.9,fr;q=1.0,en;q=0.8")
        |> fetch_query_params()
        |> LocalePlug.call([])

      # Should select 'fr' as it has highest quality and is supported
      assert conn.assigns[:locale] == :fr
    end

    test "falls back when no supported locale in Accept-Language" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "zh-CN,zh;q=0.9")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :en
    end
  end

  describe "LocalePlug - Priority Order" do
    test "query parameter takes precedence over Accept-Language header" do
      conn =
        :get
        |> conn("/?locale=es")
        |> put_req_header("accept-language", "fr")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :es
    end

    test "falls back to default when no locale specified" do
      conn =
        :get
        |> conn("/")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :en
    end
  end

  describe "serialize_translations/2" do
    setup do
      # Create a resource using the test module
      resource = %TestResource{
        id: Ash.UUID.generate(),
        name_translations: %{
          en: "Product",
          es: "Producto",
          fr: "Produit"
        },
        description_translations: %{
          en: "A great product",
          es: "Un gran producto"
        }
      }

      {:ok, resource: resource}
    end

    test "serializes translations for specified locale", %{resource: resource} do
      result = JsonApi.serialize_translations(resource, :es)

      assert result.name == "Producto"
      assert result.description == "Un gran producto"
    end

    test "falls back to default locale when translation missing", %{resource: resource} do
      result = JsonApi.serialize_translations(resource, :fr)

      assert result.name == "Produit"
      # Description not available in French, should fall back to English
      assert result.description == "A great product"
    end

    test "returns translations for all translatable attributes", %{resource: resource} do
      result = JsonApi.serialize_translations(resource, :en)

      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :description)
    end
  end

  describe "deserialize_translation_updates/2" do
    test "deserializes single locale update with locale/value format" do
      params = %{
        "name" => %{
          "locale" => "fr",
          "value" => "Nouveau Produit"
        }
      }

      result = JsonApi.deserialize_translation_updates(params, TestResource)

      assert result[:name_translations] == %{fr: "Nouveau Produit"}
    end

    test "deserializes multiple locales via translations map" do
      params = %{
        "name" => %{
          "translations" => %{
            "en" => "Updated Product",
            "es" => "Producto Actualizado",
            "fr" => "Produit Mis à Jour"
          }
        }
      }

      result = JsonApi.deserialize_translation_updates(params, TestResource)

      assert result[:name_translations][:en] == "Updated Product"
      assert result[:name_translations][:es] == "Producto Actualizado"
      assert result[:name_translations][:fr] == "Produit Mis à Jour"
    end

    test "handles simple string update for default locale" do
      params = %{
        "name" => "Simple Update"
      }

      result = JsonApi.deserialize_translation_updates(params, TestResource)

      assert result[:name] == "Simple Update"
    end

    test "handles mixed translatable and non-translatable fields" do
      params = %{
        "name" => %{
          "locale" => "es",
          "value" => "Producto"
        },
        "price" => 29.99,
        "sku" => "PROD-001"
      }

      result = JsonApi.deserialize_translation_updates(params, TestResource)

      assert result[:name_translations] == %{es: "Producto"}
      assert result[:price] == 29.99
      assert result[:sku] == "PROD-001"
    end

    test "validates locale keys and rejects invalid locales" do
      params = %{
        "name" => %{
          "translations" => %{
            "en" => "Valid",
            "invalid_locale" => "Should be rejected"
          }
        }
      }

      result = JsonApi.deserialize_translation_updates(params, TestResource)

      # Should only include valid locale
      assert Map.has_key?(result, :name_translations) == false ||
               not Map.has_key?(result[:name_translations] || %{}, :invalid_locale)
    end

    test "safely handles non-existent field names" do
      params = %{
        "non_existent_field" => %{
          "locale" => "es",
          "value" => "Some value"
        }
      }

      # Should not raise error
      # Note: Non-existent fields may be passed through for Ash validation
      assert is_map(JsonApi.deserialize_translation_updates(params, TestResource))
    end
  end

  describe "add_translation_metadata/2" do
    setup do
      resource = %TestResource{
        id: Ash.UUID.generate(),
        name_translations: %{
          en: "Product",
          es: "Producto"
        },
        description_translations: %{
          en: "Description"
        }
      }

      {:ok, resource: resource}
    end

    test "adds available locales to response metadata", %{resource: resource} do
      response = %{data: []}
      result = JsonApi.add_translation_metadata(response, resource)

      assert is_list(result.meta.available_locales)
      assert Enum.all?(result.meta.available_locales, &is_binary/1)
    end

    test "adds translation completeness percentage", %{resource: resource} do
      response = %{data: []}
      result = JsonApi.add_translation_metadata(response, resource)

      assert is_number(result.meta.translation_completeness)
      assert result.meta.translation_completeness >= 0
      assert result.meta.translation_completeness <= 100
    end

    test "adds default locale to metadata", %{resource: resource} do
      response = %{data: []}
      result = JsonApi.add_translation_metadata(response, resource)

      assert result.meta.default_locale == :en
    end

    test "merges with existing metadata", %{resource: resource} do
      response = %{
        data: [],
        meta: %{
          existing_key: "existing_value"
        }
      }

      result = JsonApi.add_translation_metadata(response, resource)

      assert result.meta.existing_key == "existing_value"
      assert Map.has_key?(result.meta, :available_locales)
    end
  end

  describe "Security - Atom Exhaustion Prevention" do
    test "rejects invalid locale strings to prevent atom exhaustion" do
      # Try to pass a long random string as locale
      long_string = String.duplicate("a", 1000)

      conn =
        :get
        |> conn("/?locale=#{long_string}")
        |> fetch_query_params()
        |> LocalePlug.call([])

      # Should fall back to default, not create new atom
      assert conn.assigns[:locale] == :en
    end

    test "only accepts whitelisted locale atoms" do
      malicious_locales = ["eval", "system", "admin", "root"]

      for locale <- malicious_locales do
        conn =
          :get
          |> conn("/?locale=#{locale}")
          |> fetch_query_params()
          |> LocalePlug.call([])

        # Should reject and fall back to default
        assert conn.assigns[:locale] == :en
      end
    end

    test "safely handles non-string locale parameters" do
      # This shouldn't crash
      conn =
        :get
        |> conn("/")
        |> Map.put(:params, %{"locale" => %{nested: "value"}})
        |> LocalePlug.call([])

      assert conn.assigns[:locale] == :en
    end
  end

  describe "Full Integration - Locale from Plug to Calculation" do
    setup do
      # Clean up ETS table before each test
      if :ets.whereis(TestResource) != :undefined do
        :ets.delete_all_objects(TestResource)
      end

      :ok
    end

    test "locale from plug flows through to calculations via Ash context" do
      # Create a test resource with translations
      product =
        Ash.create!(TestResource, %{
          name_translations: %{
            en: "Product",
            es: "Producto",
            fr: "Produit"
          },
          description_translations: %{
            en: "A great product",
            es: "Un gran producto",
            fr: "Un excellent produit"
          }
        })

      # Simulate a request with locale=es
      conn =
        :get
        |> conn("/?locale=es")
        |> fetch_query_params()
        |> LocalePlug.call([])

      # Verify the plug set the locale in Ash context
      assert conn.private.ash.context.locale == :es

      # Now fetch the resource with the context from the connection
      # This simulates what AshJsonApi would do
      context = conn.private.ash.context

      [result] =
        TestResource
        |> Ash.Query.set_context(context)
        |> Ash.Query.load([:name, :description])
        |> Ash.read!()

      # Verify the calculations used the Spanish locale
      assert result.name == "Producto"
      assert result.description == "Un gran producto"

      # Test with French locale
      conn_fr =
        :get
        |> conn("/?locale=fr")
        |> fetch_query_params()
        |> LocalePlug.call([])

      context_fr = conn_fr.private.ash.context

      [result_fr] =
        TestResource
        |> Ash.Query.set_context(context_fr)
        |> Ash.Query.load([:name, :description])
        |> Ash.read!()

      assert result_fr.name == "Produit"
      assert result_fr.description == "Un excellent produit"
    end

    test "defaults to configured locale when no query parameter provided" do
      Ash.create!(TestResource, %{
        name_translations: %{
          en: "Product",
          es: "Producto"
        }
      })

      # Request without locale parameter
      conn =
        :get
        |> conn("/")
        |> fetch_query_params()
        |> LocalePlug.call([])

      # Should default to :en
      assert conn.private.ash.context.locale == :en

      context = conn.private.ash.context

      [result] =
        TestResource
        |> Ash.Query.set_context(context)
        |> Ash.Query.load([:name])
        |> Ash.read!()

      assert result.name == "Product"
    end

    test "Accept-Language header sets context locale" do
      Ash.create!(TestResource, %{
        name_translations: %{
          en: "Product",
          es: "Producto",
          fr: "Produit"
        }
      })

      # Request with Accept-Language header
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "es-ES,es;q=0.9")
        |> fetch_query_params()
        |> LocalePlug.call([])

      assert conn.private.ash.context.locale == :es

      context = conn.private.ash.context

      [result] =
        TestResource
        |> Ash.Query.set_context(context)
        |> Ash.Query.load([:name])
        |> Ash.read!()

      assert result.name == "Producto"
    end
  end
end
