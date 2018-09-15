defmodule Apq.DocumentProviderTest do
  use Apq.Plug.TestCase
  alias Apq.TestSchema

  import Mox

  setup :verify_on_exit!

  defmodule ApqDocumentWithCompiledCacheMock do
    use Apq.DocumentProvider, cache_provider: Apq.CacheMock
  end

  defmodule ApqDocumentWithStringCacheMock do
    use Apq.DocumentProvider, cache_provider: Apq.CacheMock, cache_compiled: false
  end

  @query """
  query FooQuery($id: ID!) {
    item(id: $id) {
      name
    }
  }
  """

  @result ~s({"data":{"item":{"name":"Foo"}}})

  describe "cache compiled" do
    test "sends persisted query hash in extensions without query and no cache hit" do
      digest = sha256_hexdigest(@query)

      Apq.CacheMock
      |> expect(:get, fn ^digest -> {:ok, nil} end)

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "sends persisted query hash in extensions without query and cache hit" do
      digest = sha256_hexdigest(@query)

      blueprint = blueprint_before_variables_from_query(Apq.TestSchema, @query)

      Apq.CacheMock
      |> expect(:get, fn ^digest -> {:ok, blueprint} end)

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      assert resp_body == @result

      assert status == 200
    end

    test "sends persisted query hash in extensions with query" do
      digest = sha256_hexdigest(@query)
      query = @query

      Apq.CacheMock
      |> expect(:put, fn ^digest, %Absinthe.Blueprint{} -> {:ok, query} end)

      assert %{status: 200, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      assert resp_body == @result
    end

    test "returns error when provided hash does not match calculated query hash" do
      digest = "bogus digest"

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"ProvidedShaDoesNotMatch\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "does not halt on query without extensions" do
      assert_raise FunctionClauseError, fn ->
        conn(:post, "/", %{
          "query" => @query,
          "variables" => %{"id" => "foo"}
        })
        |> put_req_header("content-type", "application/graphql")
        |> plug_parser
        |> Absinthe.Plug.call(opts_compiled_cache())
      end
    end

    test "it passes through queries without extension to default provider" do
      opts =
        Absinthe.Plug.init(
          schema: TestSchema,
          document_providers: [
            __MODULE__.ApqDocumentWithCompiledCacheMock,
            Absinthe.Plug.DocumentProvider.Default
          ],
          json_codec: Jason
        )

      assert %{status: 200, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts)

      assert resp_body == @result
    end

    test "returns error with invalid query" do
      digest = "bogus digest"

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => %{"a" => 1},
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"QueryFormatIncorrect\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "returns error with invalid hash and valid query" do
      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => %{"a" => 1}}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"HashFormatIncorrect\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "returns error with invalid hash and no query" do
      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => %{"a" => 1}}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_compiled_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"HashFormatIncorrect\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end
  end

  describe "cache string" do
    test "sends persisted query hash in extensions without query and no cache hit" do
      digest = sha256_hexdigest(@query)

      Apq.CacheMock
      |> expect(:get, fn ^digest -> {:ok, nil} end)

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "sends persisted query hash in extensions without query and cache hit" do
      digest = sha256_hexdigest(@query)

      Apq.CacheMock
      |> expect(:get, fn ^digest -> {:ok, @query} end)

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      assert resp_body == @result

      assert status == 200
    end

    test "sends persisted query hash in extensions with query" do
      digest = sha256_hexdigest(@query)
      query = @query

      Apq.CacheMock
      |> expect(:put, fn ^digest, ^query -> {:ok, query} end)

      assert %{status: 200, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      assert resp_body == @result
    end

    test "returns error when provided hash does not match calculated query hash" do
      digest = "bogus digest"

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"ProvidedShaDoesNotMatch\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "does not halt on query without extensions" do
      assert_raise FunctionClauseError, fn ->
        conn(:post, "/", %{
          "query" => @query,
          "variables" => %{"id" => "foo"}
        })
        |> put_req_header("content-type", "application/graphql")
        |> plug_parser
        |> Absinthe.Plug.call(opts_string_cache())
      end
    end

    test "it passes through queries without extension to default provider" do
      opts =
        Absinthe.Plug.init(
          schema: TestSchema,
          document_providers: [
            __MODULE__.ApqDocumentWithStringCacheMock,
            Absinthe.Plug.DocumentProvider.Default
          ],
          json_codec: Jason
        )

      assert %{status: 200, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts)

      assert resp_body == @result
    end

    test "returns error with invalid query" do
      digest = "bogus digest"

      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => %{"a" => 1},
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => digest}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"QueryFormatIncorrect\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "returns error with invalid hash and valid query" do
      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "query" => @query,
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => %{"a" => 1}}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"HashFormatIncorrect\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end

    test "returns error with invalid hash and no query" do
      assert %{status: status, resp_body: resp_body} =
               conn(:post, "/", %{
                 "extensions" => %{
                   "persistedQuery" => %{"version" => 1, "sha256Hash" => %{"a" => 1}}
                 },
                 "variables" => %{"id" => "foo"}
               })
               |> put_req_header("content-type", "application/graphql")
               |> plug_parser
               |> Absinthe.Plug.call(opts_string_cache())

      assert resp_body == ~s({\"errors\":[{\"message\":\"HashFormatIncorrect\"}]})
      # Should be 200 per https://github.com/absinthe-graphql/absinthe_plug/pull/156
      # Will fix with release of new absinthe_plug version
      assert status == 400
    end
  end

  defp opts_compiled_cache do
    Absinthe.Plug.init(
      schema: TestSchema,
      document_providers: [__MODULE__.ApqDocumentWithCompiledCacheMock],
      json_codec: Jason
    )
  end

  defp opts_string_cache do
    Absinthe.Plug.init(
      schema: TestSchema,
      document_providers: [__MODULE__.ApqDocumentWithStringCacheMock],
      json_codec: Jason
    )
  end

  defp blueprint_before_variables_from_query(schema, query) do
    pipeline = Absinthe.Pipeline.for_document(schema, [])

    {:ok, blueprint, _} =
      Absinthe.Pipeline.run(
        query,
        pipeline |> Absinthe.Pipeline.upto(Absinthe.Phase.Document.Variables)
      )

    blueprint
  end

  defp sha256_hexdigest(query) do
    :crypto.hash(:sha256, query) |> Base.encode16(case: :lower)
  end
end