defmodule JsonApiQueryBuilder.Fields do
  @moduledoc """
  Sparse fieldset operations for JsonApiQueryBuilder
  """

  import Ecto.Query

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
end