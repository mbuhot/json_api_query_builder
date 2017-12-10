defmodule JsonApiQueryBuilder.Sort do
  @moduledoc """
  Sort operations for JsonApiQueryBuilder
  """

  import Ecto.Query

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
end