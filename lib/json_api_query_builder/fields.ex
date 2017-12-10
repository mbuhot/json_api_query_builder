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
  def fields(query, params, callback, type: type, schema: schema) do
    db_fields =
      params
      |> get_in(["fields", type])
      |> fields_string_to_list(callback, schema)

    from(x in query, select: ^db_fields)
  end

  defp fields_string_to_list(nil, _callback, schema) do
    # HACK! must explicitly select all fields, otherwise `select_merge:` may clobber it later.
    schema.__schema__(:fields)
  end
  defp fields_string_to_list(fields, callback, _schema) do
    fields
    |> String.split(",", trim: true)
    |> Kernel.++(["id"])
    |> Enum.map(callback)
  end
end