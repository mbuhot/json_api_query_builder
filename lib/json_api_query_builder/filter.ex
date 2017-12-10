defmodule JsonApiQueryBuilder.Filter do
  @moduledoc """
  Filter operations for JsonApiQueryBuilder.
  """

  @doc """
  Applies filter conditions from a parsed JSON-API request to an `Ecto.Queryable.t`.

  Each filter condition will be cause the given callback to be invoked with the query, attribute and value.

  ## Relationship Filters

  There are two types of relationship filters: join filters and preload filters.

  Join filters use a dotted notation, eg: `"comments.author.articles"`, and will be used to filter the primary data using a SQL inner join.

  Eg: `%{"filter" => %{"author.has_bio" => 1}}` can be used to find all articles where the related author has a bio in the database.


  Preload filters use a nested notation, eg: `%{"author" => %{"has_bio" => 1}}`, and will only be used to filter the relationships specified in the `include` parameter.

  Eg: `%{"include" => "author", "filter" => %{"author" => %{"has_bio" => 1}}}` can be used to find all articles, and include the related authors if they have a bio.

  ## Example

      JsonApiQueryBuilder.Filter.filter(
        Article,
        %{"filter" => %{"tag" => "animals", "author.has_bio" => "1", "author.has_image" => "1", "comments" => %{"body" => "Great"}}},
        &apply_filter/3,
        relationships: ["author", "comments"]
      )

  The example above will cause the `apply_filter/3` callback to be invoked twice:
    - `apply_filter(query, "tag", "animals")`
    - `apply_filter(query, "author", %{"filter" => %{"has_bio" => "1", "has_image" => "1"}})`

    Where `apply_filter` would be implemented like:

    ```
    def apply_filter(query, "tag", val), do: from(article in query, where: ^val in article.tag_list)
    def apply_filter(query, "author", params) do
      user_query = from(User.Query.build(params), select: [:id])
      from(article in query, join: user in ^subquery(user_query), on: article.user_id == user.id)
    end
    ```
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
      String.starts_with?(filter, relationship <> ".")
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
      |> Enum.map(fn {k, v} -> {String.trim_leading(k, relation <> "."), v} end)
      |> Enum.into(%{})
    }
  end
end