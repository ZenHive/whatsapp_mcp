defmodule WhatsappMcp.Database.Helpers do
  @moduledoc """
  Shared helper functions for database operations.

  Provides low-level SQLite utilities and text processing functions
  used by all database submodules.

  ## SQL Fragment Safety

  Some database modules build SQL queries by interpolating fragments returned
  by functions in this module (e.g., `build_time_filter/2`). This pattern is
  **safe** because:

  1. Fragment functions return hardcoded strings only (never user input)
  2. User-provided values are always passed via parameterized `?` placeholders
  3. User input that goes into LIKE patterns is escaped via `escape_like_pattern/1`

  Example of safe pattern:
  ```elixir
  {time_filter, params} = Helpers.build_time_filter(before, after_ts)
  query = "SELECT * FROM messages WHERE chat_jid = ? \#{time_filter}"
  execute_query(conn, query, [chat_jid] ++ params)
  ```

  The `time_filter` string comes from `build_time_filter/2` which only returns
  hardcoded SQL like `"AND m.timestamp < ?"`. The actual user-provided timestamp
  value goes into `params` and is safely bound via the `?` placeholder.
  """

  # Type definitions for internal use
  @typedoc "Result from database query - errors are atoms from Exqlite or descriptive strings"
  @type db_result :: {:ok, [[term()]]} | {:error, atom() | String.t()}

  @typedoc "Time filter tuple with SQL clause and params"
  @type time_filter :: {String.t(), [String.t()]}

  @doc """
  Executes a query with a readonly connection, ensuring cleanup via try/after.
  """
  @spec with_readonly_connection(String.t(), String.t(), [term()]) :: db_result()
  def with_readonly_connection(db_path, query, params) do
    case Exqlite.Sqlite3.open(db_path, mode: :readonly) do
      {:ok, conn} ->
        try do
          execute_query(conn, query, params)
        after
          Exqlite.Sqlite3.close(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Executes a query on an open database connection.
  """
  @spec execute_query(Exqlite.Sqlite3.db(), String.t(), [term()]) :: db_result()
  def execute_query(conn, query, params) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, query),
         :ok <- Exqlite.Sqlite3.bind(stmt, params),
         {:ok, rows} <- fetch_all_rows(conn, stmt),
         :ok <- Exqlite.Sqlite3.release(conn, stmt) do
      {:ok, rows}
    end
  end

  @doc """
  Fetches all rows from a prepared statement.
  """
  @spec fetch_all_rows(Exqlite.Sqlite3.db(), Exqlite.Sqlite3.statement(), [[term()]]) ::
          {:ok, [[term()]]} | {:error, term()}
  def fetch_all_rows(conn, stmt, acc \\ []) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> fetch_all_rows(conn, stmt, [row | acc])
      :done -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cleans message content, handling nil and binary data.

  Returns nil for nil input, the original text if printable,
  or a placeholder for binary/system messages.
  """
  @spec clean_message(term()) :: String.t() | nil
  def clean_message(nil), do: nil

  def clean_message(text) when is_binary(text) do
    if String.printable?(text) do
      text
    else
      "[Binary/System message]"
    end
  end

  def clean_message(_), do: nil

  @doc """
  Extracts phone number from JID.

  ## Examples

      iex> extract_phone("12025551234@s.whatsapp.net")
      "12025551234"

      iex> extract_phone("144555781402794@lid")
      "144555781402794"

  """
  @spec extract_phone(String.t()) :: String.t()
  def extract_phone(jid) when is_binary(jid) do
    case String.split(jid, "@", parts: 2) do
      [phone, _domain] -> phone
      [jid_without_at] -> jid_without_at
    end
  end

  @doc """
  Escapes SQL LIKE pattern special characters to treat them as literals.

  This prevents user input like "50%" from matching unintended patterns.
  """
  @spec escape_like_pattern(String.t()) :: String.t()
  def escape_like_pattern(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  Builds a time filter clause for message queries.

  Returns a tuple of {sql_clause, params} for use in WHERE clauses.

  ## Parameters

    * `before` - Only messages before this timestamp
    * `after_ts` - Only messages after this timestamp

  ## Timezone Handling

  **All timestamps in the database are stored in UTC.**

  When filtering by time:
  - If you provide a timezone (e.g., "2025-12-11T10:00:00+08:00"), it's used as-is
  - If you provide "Z" suffix (e.g., "2025-12-11T02:00:00Z"), it's used as-is
  - If you omit timezone (e.g., "2025-12-11T10:00:00"), UTC (+00:00) is assumed

  **For AI tools**: Always ask the user for their timezone when filtering by time.
  Convert user's local time to UTC before querying.

  ## Examples

      build_time_filter("2025-12-11T10:00:00Z", nil)      # UTC explicit
      build_time_filter("2025-12-11T10:00:00+00:00", nil) # UTC explicit
      build_time_filter("2025-12-11T10:00:00", nil)       # UTC assumed

  """
  @spec build_time_filter(String.t() | nil, String.t() | nil) :: time_filter()
  def build_time_filter(before, after_ts \\ nil)

  def build_time_filter(nil, nil), do: {"", []}

  def build_time_filter(before, nil) do
    {"AND m.timestamp < ?", [normalize_timestamp(before)]}
  end

  def build_time_filter(nil, after_ts) do
    {"AND m.timestamp > ?", [normalize_timestamp(after_ts)]}
  end

  def build_time_filter(before, after_ts) do
    {"AND m.timestamp < ? AND m.timestamp > ?", [normalize_timestamp(before), normalize_timestamp(after_ts)]}
  end

  @doc """
  Normalizes a timestamp to match the database format.

  The database stores timestamps in UTC as "YYYY-MM-DD HH:MM:SS+00:00".
  This function converts common input formats:
  - ISO8601 with T separator: "2025-12-11T10:00:00" -> "2025-12-11 10:00:00"
  - Adds UTC timezone (+00:00) if missing

  ## Examples

      iex> normalize_timestamp("2025-12-11T10:00:00")
      "2025-12-11 10:00:00+00:00"

      iex> normalize_timestamp("2025-12-11 10:00:00+00:00")
      "2025-12-11 10:00:00+00:00"

      iex> normalize_timestamp("2025-12-11T10:00:00Z")
      "2025-12-11 10:00:00Z"

  """
  @spec normalize_timestamp(String.t()) :: String.t()
  def normalize_timestamp(timestamp) when is_binary(timestamp) do
    # Default timezone is UTC (all timestamps stored in UTC)
    default_tz = "+00:00"

    timestamp
    # Replace T separator with space to match DB format
    |> String.replace("T", " ")
    # Add default timezone if no timezone info present
    |> maybe_add_timezone(default_tz)
  end

  defp maybe_add_timezone(timestamp, default_tz) do
    # Check if timestamp already has timezone info
    # Patterns: +HH:MM, -HH:MM, Z
    if Regex.match?(~r/[+-]\d{2}:\d{2}$/, timestamp) or String.ends_with?(timestamp, "Z") do
      timestamp
    else
      timestamp <> default_tz
    end
  end
end
