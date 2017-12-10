[![Build Status](https://img.shields.io/travis/mbuhot/json_api_query_builder.svg?branch=master)](https://travis-ci.org/mbuhot/json_api_query_builder)
[![Hex.pm](https://img.shields.io/hexpm/v/json_api_query_builder.svg)](https://hex.pm/packages/json_api_query_builder)
[![HexDocs](https://img.shields.io/badge/api-docs-yellow.svg)](https://hexdocs.pm/json_api_query_builder/)
[![Inch CI](http://inch-ci.org/github/mbuhot/json_api_query_builder.svg)](http://inch-ci.org/github/mbuhot/json_api_query_builder)
[![License](https://img.shields.io/hexpm/l/json_api_query_builder.svg)](https://github.com/mbuhot/json_api_query_builder/blob/master/LICENSE)

# JSON-API Query Builder

Build Ecto queries from JSON-API requests.

Docs can be found at [https://hexdocs.pm/json_api_query_builder](https://hexdocs.pm/json_api_query_builder).

## Installation

The package can be installed by adding `json_api_query_builder` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:json_api_query_builder, "~> 0.1"}]
end
```

## Features

JSON-API Query Builder can be used to construct an efficient Ecto query to handle the following kinds of requests, in arbitrary combinations.

### Sparse Fieldsets

Get all articles, including only the `title` and `description` fields

`/blog/articles/?fields[article]=title,description`

### Sorting

Get all articles, sorted by `category` ascending and `published` descending

`/blog/articles/?sort=category,-published`

### Included Resources

Get all articles, including related author, comments and comments user

`/blog/articles/?include=author,comments,comments.user`

### Attribute Filters

Get all articles with the animals `tag`

`/blog/articles/?filter[tag]=animals`

### Filter by related resource

Get all users who have an article with the animals `tag`

`/blog/users?filter[article.tag]=animals`

### Filter included resources

Get all users, including related articles that have the animals `tag`

`/blog/users?include=articles&filter[article][tag]=animals`

### Pagination

TODO

## Usage

For each Ecto schema, create a related query builder module:

```elixir
defmodule Article do
  use Ecto.Schema

  schema "articles" do
    field :body, :string
    field :description, :string
    field :slug, :string
    field :tag_list, {:array, :string}
    field :title, :string
    belongs_to :author, User, foreign_key: :user_id
    has_many :comments, Comment
    timestamps()
  end

  defmodule Query do
    use JsonApiQueryBuilder,
      schema: Article,
      type: "article",
      relationships: ["author", "comments"]

    @impl JsonApiQueryBuilder
    def filter(query, "tag", value), do: from(a in query, where: ^value in a.tag_list)
    def filter(query, "comments", params) do
      comment_query = from(Comment.Query.build(params), select: [:article_id], distinct: true)
      from a in query, join: c in ^subquery(comment_query), on: a.id == c.article_id
    end
    def filter(query, "author", params) do
      user_query = from(User.Query.build(params), select: [:id])
      from a in query, join: u in ^subquery(user_query), on: a.user_id == u.id
    end

    @impl JsonApiQueryBuilder
    def include(query, "comments", comment_params) do
      from query, preload: [comments: ^Comment.Query.build(comment_params)]
    end
    def include(query, "author", author_params) do
      from query, preload: [author: ^User.Query.build(author_params)]
    end
  end
end
```

Then in an API request handler, use the query builder:

```elixir
defmodule ArticleController do
  use MyAppWeb, :controller

  def index(conn, params) do
    articles =
      params
      |> Article.Query.build()
      |> MyApp.Repo.all()

    # pass data and opts as expected by `ja_serializer`
    render("index.json-api", data: articles, opts: [
      fields: params["fields"],
      include: params["include"]
    ])
  end
end
```

## License

MIT

## Contributing

GitHub issues and pull requests welcome.

