defmodule SignDictWeb.Backend.CSVExportSuggestionsController do
  use SignDictWeb, :controller

  alias SignDict.Domain

  def show(conn = %{assigns: %{current_user: current_user}}, _params) do
    if Canada.Can.can?(current_user, "statistic", %SignDict.Entry{}) do
      do_export(conn)
    else
      conn
      |> put_flash(:info, gettext("You cannot view this page."))
      |> redirect(to: backend_dashboard_path(conn, :index))
    end
  end

  defp do_export(conn) do
    conn =
      conn
      |> put_resp_header("content-disposition", "attachment; filename=statistic_suggestions.csv")
      |> put_resp_content_type("text/csv")
      |> send_chunked(200)

    {:ok, conn} =
      Repo.transaction(fn ->
        conn.host
        |> Domain.for()
        |> build_export_query()
        |> chunk_data(conn)
      end)

    conn
  end

  defp chunk_data(data, conn) do
    Enum.reduce_while(data, conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} ->
          {:cont, conn}

        {:error, :closed} ->
          {:halt, conn}
      end
    end)
  end

  def build_export_query(domain, batch_size \\ 500) do
    query = """
      select word, description, trim(both '"' from to_json(inserted_at)::text)
        from suggestions
        where domain_id = $1
    """

    csv_header = [["Word", "Description", "Time"]]

    Ecto.Adapters.SQL.stream(Repo, query, [domain.id], max_rows: batch_size)
    |> Stream.flat_map(fn item ->
      item.rows
    end)
    |> (fn stream -> Stream.concat(csv_header, stream) end).()
    |> CSV.encode()
  end
end
