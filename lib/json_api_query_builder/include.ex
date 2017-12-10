defmodule JsonApiQueryBuilder.Include do
  @moduledoc """
  Related resource include operations for JsonApiQueryBuilder
  """

  @doc """
  Applies related resource inclusion from a parsed JSON-API request to an `Ecto.Queryable.t` as preloads.

  The given callback will be invoked for each included relationship with a new JSON-API style request.
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