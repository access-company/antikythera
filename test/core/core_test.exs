# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCoreTest do
  use Croma.TestCase
  alias AntikytheraEal.ClusterConfiguration

  setup do
    :meck.new(ClusterConfiguration, [:passthrough])

    on_exit(fn ->
      :meck.unload()
    end)
  end

  defp mock_health_check_grace_period(grace_period) do
    :meck.expect(
      ClusterConfiguration,
      :health_check_grace_period,
      fn ->
        grace_period
      end
    )
  end

  test "calculate_connection_retry_count_from_health_check_grace_period/1 should return an appropriate retry count" do
    Enum.each(
      [
        {0, 0},
        {400, 80},
        {401, 80}
      ],
      fn {grace_period, expected_retry_count} ->
        mock_health_check_grace_period(grace_period)

        assert AntikytheraCore.calculate_connection_retry_count_from_health_check_grace_period() ==
                 expected_retry_count
      end
    )
  end
end
