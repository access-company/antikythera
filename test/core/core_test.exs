# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCoreTest do
  use Croma.TestCase
  alias AntikytheraEal.ClusterConfiguration

  setup do
    :meck.new(ClusterConfiguration, [:passthrough])

    on_exit(&:meck.unload/0)
  end

  defp mock_health_check_grace_period_in_seconds(grace_period) do
    :meck.expect(
      ClusterConfiguration,
      :health_check_grace_period_in_seconds,
      fn ->
        grace_period
      end
    )
  end

  test "calculate_connection_trial_count_from_health_check_grace_period/0 should return an appropriate trial count" do
    Enum.each(
      [
        {0, 1},
        {300, 60},
        {301, 60}
      ],
      fn {grace_period, expected_trial_count} ->
        mock_health_check_grace_period_in_seconds(grace_period)

        assert AntikytheraCore.calculate_connection_trial_count_from_health_check_grace_period() ==
                 expected_trial_count
      end
    )
  end

  test "add_log_filters/0 registers the primary filters that drop noisy OTP reports" do
    primary_filter_ids = :logger.get_primary_config().filters |> Keyword.keys()
    assert :antikythera_reject_progress in primary_filter_ids
    assert :antikythera_reject_mnesia_down in primary_filter_ids
    assert :antikythera_reject_poolsup_kill in primary_filter_ids
  end

  test "the alert backend handler is registered via logger_backends" do
    assert LoggerBackends in :logger.get_handler_ids()
  end
end
