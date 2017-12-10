defmodule JsonApiQueryBuilder do
  @moduledoc """
  Functions for building an Ecto query from a JSON-API request
  """

  @doc """
  Callback responsible for adding a filter criteria to a query.

  Attribute filters will generally add a `where:` condition to the query.
  Relationship filters will generally add a `join:` based on a subquery.
  When applying a filter to a has-many relationship, take care to `select:` the foreign key with `distinct: true` to avoid duplicated results.
  For filtering a belongs-to relationships, selecting the primary key is all that is needed.

  ## Example

      @impl JsonApiQueryBuilder
      def filter(query, "tag", value), do: from(article in query, where: ^value in article.tag_list)
      def filter(query, "comments", params) do
        comment_query = from(Comment.Query.build(params), select: [:article_id], distinct: true)
        from article in query, join: comment in ^subquery(comment_query), on: article.id == comment.article_id
      end
      def filter(query, "author", params) do
        user_query = from(User.Query.build(params), select: [:id])
        from article in query, join: user in ^subquery(user_query), on: article.user_id == user.id
      end
  """
  @callback filter(Ecto.Queryable.t, String.t, any) :: Ecto.Queryable.t

  @doc """
  Callback responsible for adding an included resource via `preload`.

  Use `select_merge: [:id]` to ensure that the primary key of the schema is selected, as it is required for `preload`.

  ## Example

      @impl JsonApiQueryBuilder
      def include(query, "comments", comment_params) do
        from query, select_merge: [:id], preload: [comments: ^Comment.Query.build(comment_params)]
      end
      def include(query, "author", author_params) do
        from query, select_merge: [:id], preload: [author: ^User.Query.build(author_params)]
      end
  """
  @callback include(Ecto.Queryable.t, String.t, map) :: Ecto.Queryable.t

  @doc """
  Optional callback responsible for mapping a JSON-API field string to an Ecto schema field.

  Defaults to `String.to_existing_atom/1`.

  ## Example

      @impl JsonApiQueryBuilder
      def field("username"), do: :name
      def field("price"), do: :unit_price
      def field(other), do: String.to_existing_atom(other)
  """
  @callback field(String.t) :: atom

  defmacro __using__(schema: schema, type: type, relationships: relationships) do
    quote do
      import Ecto.Query

      @behaviour JsonApiQueryBuilder

      @schema unquote(schema)
      @api_type unquote(type)
      @relationships unquote(relationships)

      @doc """
      Builds an `Ecto.Queryable.t` from parsed JSON-API request parameters.

      ## Example:

          User.Query.build(%{
            "filter" => %{
              "articles.tag" => "animals",
              "comments" => %{
                "body" => "Boo"
              }
            },
            "include" => "articles.comments",
            "fields" => %{"user" => "id,bio"}
          })

          #Ecto.Query<
            from u in Blog.User,
            join: a in ^#Ecto.Query<
              from a in subquery(
                from a in Blog.Article,
                where: ^"animals" in a.tag_list,
                distinct: true,
                select: [:user_id]
              )
            >,
            on: u.id == a.user_id,
            select: [:id, :bio],
            preload: [
              articles: #Ecto.Query<
                from a in Blog.Article,
                preload: [comments: #Ecto.Query<from c in Blog.Comment>]
              >
            ]
          >
      """
      @spec build(map) :: Ecto.Queryable.t
      def build(params) do
        from(@schema)
        |> filter(params)
        |> fields(params)
        |> sort(params)
        |> include(params)
      end

      @doc """
      Applies filter conditions from a parsed JSON-API request to an `Ecto.Queryable.t`
      """
      @spec filter(Ecto.Queryable.t, map) :: Ecto.Queryable.t
      def filter(query, params) do
        JsonApiQueryBuilder.filter(query, params, &filter/3, relationships: @relationships)
      end

      @doc """
      Applies sparse fieldset selection from a parsed JSON-API request to an `Ecto.Queryable.t`
      """
      @spec fields(Ecto.Queryable.t, map) :: Ecto.Queryable.t
      def fields(query, params) do
        JsonApiQueryBuilder.fields(query, params, &field/1, type: @api_type)
      end

      @doc """
      Applies sorting from a parsed JSON-API request to an `Ecto.Queryable.t`
      """
      @spec sort(Ecto.Queryable.t, map) :: Ecto.Queryable.t
      def sort(query, params) do
        JsonApiQueryBuilder.sort(query, params, &field/1)
      end

      @doc """
      Applies related resource inclusion from a parsed JSON-API request to an `Ecto.Queryable.t` as preloads.

      To filter the included relationship, use a nested syntax instead of a dotted syntax:

      ## Filter included resources


      """
      @spec include(Ecto.Queryable.t, map) :: Ecto.Queryable.t
      def include(query, params) do
        JsonApiQueryBuilder.include(query, params, &include/3)
      end

      @doc """
      Maps a JSON-API field name to Ecto schema field name using `String.to_existing_atom/1`
      """
      @impl JsonApiQueryBuilder
      def field(str), do: String.to_existing_atom(str)

      defoverridable [field: 1]
    end
  end

  import Ecto.Query

  @doc """
  Applies filter conditions from a parsed JSON-API request to an `Ecto.Queryable.t`.

  Each filter condition will be cause the given callback to be invoked with the query, attribute and value.

  ## Relationship Filters

  There are two types of relationship filters: join filters and preload filters.
  Join filters use a dotted notation, eg: `"comments.author.articles"`, and will be used to filter the primary data using a SQL inner join.
  So `%{"filter" => %{"author.has_bio" => 1}}` can be used to find all articles where the related author has a bio in the database.

  Preload filters use a nested notation, eg: `%{"author" => %{"has_bio" => 1}}`, and will only be used to filter the relationships specified in the `include` parameter.
  So `%{"include" => "author", "filter" => %{"author" => %{"has_bio" => 1}}}` can be used to find all articles, and include the related authors if they have a bio.

  ## Example

      JsonApiQueryBuilder.filter(
        Article,
        %{"filter" => %{"tag" => "animals", "author.has_bio" => "1", "author.has_image" => "1", "comments" => %{"body" => "Great"}}},
        &apply_filter/3,
        relationships: ["author", "comments"]
      )

  The example above will case the `apply_filter/3` callback to be invoked twice:
    - `apply_filter(query, "tag", "animals")`
    - `apply_filter(query, "author", %{"filter" => %{"has_bio" => "1", "has_image" => "1"}})

    `apply_filter` would be implemented like:

        def apply_filter(query, "tag", val), do: from(article in query, where: ^val in article.tag_list)
        def apply_filter(query, "author", params) do
          user_query = from(User.Query.build(params), select: [:id])
          from(article in query, join: user in ^subquery(user_query), on: article.user_id == user.id)
        end
  """
  @spec filter(Ecto.Queryable.t, map, function, [relationships: [String.t]]) :: Ecto.Queryable.t
  def filter(query, params, callback, relationships: relationships) do
    JsonApiQueryBuilder.Filter.filter(query, params, callback, relationships: relationships)
  end

  @doc """
  Applies sparse fieldset selection from a parsed JSON-API request to an `Ecto.Queryable.t`

  The given callback will be used to map from API field name strings to Ecto schema atoms.
  """
  @spec fields(Ecto.Queryable.t, map, function, [type: String.t]) :: Ecto.Queryable.t
  def fields(query, params, callback, type: type) do
    case get_in(params, ["fields", type]) do
      nil -> query
      field_string ->
        field_list = ["id" | String.split(field_string, ",", trim: true)]
        db_fields = Enum.map(field_list, callback)

        from(query, select: ^db_fields)
    end
  end

  @doc """
  Applies sorting from a parsed JSON-API request to an `Ecto.Queryable.t`

  The given callback will be used to map from API field name strings to Ecto schema atoms.
  """
  def sort(query, %{"sort" => sort_string}, callback) do
    sort =
      sort_string
      |> String.split(",", trim: true)
      |> Enum.map(fn
          "-" <> field -> {:desc, callback.(field)}
          field -> {:asc, callback.(field)}
        end)
    from(query, order_by: ^sort)
  end
  def sort(query, _params, _callback), do: query

  @doc """
  Applies related resource inclusion from a parsed JSON-API request to an `Ecto.Queryable.t` as preloads.

  The given callback will be invoked for each included relationship with a new JSON-API style request.
  """
  @spec include(Ecto.Queryable.t, map, function) :: Ecto.Queryable.t
  def include(query, params, callback) do
    JsonApiQueryBuilder.Include.include(query, params, callback)
  end

  defmodule Include do
    @moduledoc """
    Internal module for implementation of JsonApiQueryBuilder.include operation.
    """

    @doc """
    See `JsonApiQueryBuilder.include/3` for details.
    """
    @spec include(Ecto.Queryable.t, map, function) :: Ecto.Queryable.t
    def include(query, params, callback) do
      includes =
        params
        |> Map.get("include", "")
        |> group_includes()

      Enum.reduce(includes, query, fn
        {relationship, related_includes}, query ->
          related_params = %{
            "include" => related_includes,
            "filter" => (get_in(params, ["filter", relationship]) || %{}),
            "fields" => params["fields"]
          }
          callback.(query, relationship, related_params)
      end)
    end

    @doc """
    Groups the `include` string by leading path segment.

    ## Example

        iex> JsonApiQueryBuilder.Include.group_includes("a,a.b,a.b.c,a.d,e")
        [{"a", "b,b.c,d"}, {"e", ""}]
    """
    @spec group_includes(String.t) :: [{String.t, String.t}]
    def group_includes(includes) do
      includes
      |> String.split(",", trim: true)
      |> Enum.map(&String.split(&1, ".", parts: 2))
      |> Enum.group_by(&hd/1, &Enum.drop(&1, 1))
      |> Enum.map(fn {k, v} -> {k, Enum.join(List.flatten(v), ",")} end)
    end
  end

  defmodule Filter do
    @moduledoc """
    Internal module to implementing JsonApiQueryBuilder.filter operation.
    """

    @doc """
    See `JsonApiQueryBuilder.filter/4` for details.
    """
    @spec filter(Ecto.Queryable.t, map, function, [relationships: [String.t]]) :: Ecto.Queryable.t
    def filter(query, params, callback, relationships: relationships) do
      query
      |> apply_attribute_filters(params, callback, relationships)
      |> apply_join_filters(params, callback, relationships)
    end

    @spec apply_attribute_filters(Ecto.Queryable.t, map, function, [String.t]) :: Ecto.Queryable.t
    defp apply_attribute_filters(query, params, callback, relationships) do
      params
      |> Map.get("filter", %{})
      |> Enum.filter(fn {k, _v} -> not is_relationship_filter?(relationships, k) end)
      |> Enum.reduce(query, fn {k, v}, query -> callback.(query, k, v) end)
    end

    @spec apply_join_filters(Ecto.Queryable.t, map, function, [String.t]) :: Ecto.Queryable.t
    defp apply_join_filters(query, params, callback, relationships) do
      params
      |> Map.get("filter", %{})
      |> Enum.filter(fn {k, _v} -> is_join_filter?(relationships, k) end)
      |> Enum.group_by(fn {k, _v} -> first_relationship_segment(k) end)
      |> Enum.map(fn {relation, rel_filters} -> trim_leading_relationship_from_keys(relation, rel_filters) end)
      |> Enum.reduce(query, fn {relation, params}, query -> callback.(query, relation, %{"filter" => params}) end)
    end

    @doc """
    Tests if the given string is either a join filter or a preload filter

    ## Example

        iex> JsonApiQueryBuilder.Filter.is_relationship_filter?(["articles", "comments"], "articles.comments.user")
        true
        iex> JsonApiQueryBuilder.Filter.is_relationship_filter?(["articles", "comments"], "comments")
        true
        iex> JsonApiQueryBuilder.Filter.is_relationship_filter?(["articles", "comments"], "email")
        false
    """
    @spec is_relationship_filter?([String.t], String.t) :: boolean
    def is_relationship_filter?(relationships, filter) do
      is_join_filter?(relationships, filter) || is_preload_filter?(relationships, filter)
    end

    @doc """
    Tests if the given string is a join filter.

    ## Example

        iex> JsonApiQueryBuilder.Filter.is_join_filter?(["articles", "comments"], "articles.comments.user")
        true
        iex> JsonApiQueryBuilder.Filter.is_join_filter?(["articles", "comments"], "comments")
        false
        iex> JsonApiQueryBuilder.Filter.is_join_filter?(["articles", "comments"], "email")
        false
    """
    @spec is_join_filter?([String.t], String.t) :: boolean
    def is_join_filter?(relationships, filter) do
      Enum.any?(relationships, fn relationship ->
        String.starts_with?(filter, relationship<>".")
      end)
    end

    @doc """
    Tests if the given string is a join preload filter.

    ## Example

        iex> JsonApiQueryBuilder.Filter.is_preload_filter?(["articles", "comments"], "articles.comments.user")
        false
        iex> JsonApiQueryBuilder.Filter.is_preload_filter?(["articles", "comments"], "comments")
        true
        iex> JsonApiQueryBuilder.Filter.is_preload_filter?(["articles", "comments"], "email")
        false
    """
    @spec is_preload_filter?([String.t], String.t) :: boolean
    def is_preload_filter?(relationships, filter) do
      filter in relationships
    end

    @doc """
    Extract the first segment of a dotted relationship path.

    ## Example

        iex> JsonApiQueryBuilder.Filter.first_relationship_segment("a.b.c")
        "a"
    """
    @spec first_relationship_segment(String.t) :: String.t
    def first_relationship_segment(path) do
      path
      |> String.split(".", parts: 2)
      |> hd()
    end

    @doc """
    Removes the leading path segment from map keys after grouping has been applied.


    ## Example

        iex> JsonApiQueryBuilder.Filter.trim_leading_relationship_from_keys("article", [{"article.tag", "animals"}, {"article.comments.user.name", "joe"}])
        {"article", %{"comments.user.name" => "joe", "tag" => "animals"}}
    """
    @spec trim_leading_relationship_from_keys(String.t, list) :: {String.t, map}
    def trim_leading_relationship_from_keys(relation, rel_filters) do
      {
        relation,
        rel_filters
        |> Enum.map(fn {k, v} -> {String.trim_leading(k, relation<>"."), v} end)
        |> Enum.into(%{})
      }
    end
  end
end
