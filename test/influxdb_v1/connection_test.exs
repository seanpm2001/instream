defmodule Instream.InfluxDBv1.ConnectionTest do
  use ExUnit.Case, async: true

  @moduletag :"influxdb_exclude_2.0"
  @moduletag :"influxdb_exclude_2.1"
  @moduletag :"influxdb_exclude_2.2"

  alias Instream.TestHelpers.TestConnection

  defmodule TestSeries do
    use Instream.Series

    series do
      measurement "data_write_struct"

      tag :bar
      tag :foo

      field :value
    end
  end

  @tags %{foo: "foo", bar: "bar"}

  test "ping connection" do
    assert :pong = TestConnection.ping()
  end

  test "status connection" do
    assert :ok = TestConnection.status()
  end

  test "version connection" do
    assert is_binary(TestConnection.version())
  end

  test "read using params" do
    test_field = ~S|string field value, only " need be quoted|
    test_tag = ~S|tag,value,with"commas"|

    :ok =
      TestConnection.write([
        %{
          measurement: "params",
          tags: %{foo: test_tag},
          fields: %{value: test_field}
        }
      ])

    query = "SELECT value FROM params WHERE foo = $foo_val"
    params = %{foo_val: test_tag}

    assert %{results: [%{series: [%{name: "params", values: [[_, ^test_field]]}]}]} =
             TestConnection.query(query, params: params)
  end

  @tag :"influxdb_include_1.8"
  test "read using flux query" do
    measurement = "flux"

    :ok =
      TestConnection.write([
        %{
          measurement: measurement,
          tags: @tags,
          fields: %{numeric: 0.66, boolean: true}
        }
      ])

    result =
      TestConnection.query(
        """
        from(bucket:"test_database/autogen")
        |> range(start: -1h)
        |> filter(fn: (r) => r._measurement == "#{measurement}")
        """,
        query_language: :flux,
        result_as: :csv
      )

    assert [
             [
               %{
                 "_field" => "boolean",
                 "_measurement" => ^measurement,
                 "_value" => true,
                 "bar" => "bar",
                 "foo" => "foo",
                 "result" => "_result"
               }
             ],
             [
               %{
                 "_field" => "numeric",
                 "_measurement" => ^measurement,
                 "_value" => 0.66,
                 "bar" => "bar",
                 "foo" => "foo",
                 "result" => "_result"
               }
             ]
           ] = result
  end

  test "write data" do
    measurement = "write_data"

    :ok =
      TestConnection.write([
        %{
          measurement: measurement,
          tags: @tags,
          fields: %{value: 0.66}
        }
      ])

    assert %{results: [%{series: [%{tags: values_tags, values: value_rows}]}]} =
             TestConnection.query("SELECT * FROM #{measurement} GROUP BY *")

    assert @tags == values_tags
    assert 0 < length(value_rows)
  end

  test "writing series struct" do
    :ok =
      %{
        bar: "bar",
        foo: "foo",
        value: 17
      }
      |> TestSeries.from_map()
      |> TestConnection.write()

    assert %{results: [%{series: [%{tags: values_tags, values: value_rows}]}]} =
             TestConnection.query("SELECT * FROM #{TestSeries.__meta__(:measurement)} GROUP BY *")

    assert @tags == values_tags
    assert 0 < length(value_rows)
  end
end
