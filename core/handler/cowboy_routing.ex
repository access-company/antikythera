# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.CowboyRouting do
  alias Antikythera.{Env, Domain, GearName, GearNameStr}
  alias AntikytheraCore.GearModule
  alias AntikytheraCore.Config.Gear, as: GearConfig
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Handler.{GearAction, Healthcheck, SystemInfoExporter}
  require AntikytheraCore.Logger, as: L

  @healthcheck_route_initialized   {"/healthcheck"              , Healthcheck.Initialized      , nil}
  @healthcheck_route_uninitialized {"/healthcheck"              , Healthcheck.Uninitialized    , nil}
  @version_report_route            {"/versions"                 , SystemInfoExporter.Versions  , nil}
  @total_error_count_route         {"/error_count/_total"       , SystemInfoExporter.ErrorCount, :total}
  @per_app_error_count_route       {"/error_count/:otp_app_name", SystemInfoExporter.ErrorCount, :per_otp_app}

  defun compiled_routes(gear_names :: [GearName.t], initialized? :: v[boolean]) :: :cowboy_router.dispatch_rules do
    gear_routes = Enum.flat_map(gear_names, &per_gear_domain_pathroutes_pairs/1)
    :cowboy_router.compile(gear_routes ++ wildcard_domain_routes(initialized?))
  end

  defunp wildcard_domain_routes(initialized? :: v[boolean]) :: :cowboy_router.routes do
    path_rules = [
      (if initialized?, do: @healthcheck_route_initialized, else: @healthcheck_route_uninitialized),
      @version_report_route,
      @total_error_count_route,
      @per_app_error_count_route,
    ]
    [{:_, path_rules}]
  end

  defunp per_gear_domain_pathroutes_pairs(gear_name :: v[GearName.t]) :: :cowboy_router.routes do
    routes = [
      static_file_serving_route(gear_name),
      normal_routes(gear_name),
    ] |> Enum.reject(&is_nil/1)
    domains_of(gear_name) |> Enum.map(fn domain -> {domain, routes} end)
  end

  @typep route_path :: {String.t, module, any}

  defunp static_file_serving_route(gear_name :: v[GearName.t]) :: nil | route_path do
    router_module = GearModule.router(gear_name)
    try do
      router_module.static_prefix()
    rescue
      UndefinedFunctionError -> nil
    end
    |> case do
      nil    -> nil
      prefix -> {"#{prefix}/[...]", :cowboy_static , {:priv_dir, gear_name, "static", [{:mimetypes, :cow_mimetypes, :all}]}}
    end
  end

  defunp normal_routes(gear_name :: v[GearName.t]) :: route_path do
    {"/[...]", GearAction.Web, gear_name}
  end

  defunp domains_of(gear_name :: v[GearName.t]) :: [Domain.t] do
    custom_domains =
      case ConfigCache.Gear.read(gear_name) do
        nil                           -> []
        %GearConfig{domains: domains} -> domains
      end
    [default_domain(gear_name) | custom_domains]
  end

  defun update_routing(gear_names :: [GearName.t], initialized? :: v[boolean]) :: :ok do
    if Env.no_listen?() do
      :ok
    else
      L.info("updating cowboy routing (initialized?=#{initialized?})")
      :cowboy.set_env(:antikythera_http_listener, :dispatch, compiled_routes(gear_names, initialized?))
    end
  end

  #
  # Handling domains
  #
  @deployments         Application.fetch_env!(:antikythera, :deployments)
  @current_compile_env Env.compile_env()

  # This can also used by administrative gears
  defun default_domain(gear_name :: v[GearName.t | GearNameStr.t], env :: v[Env.t] \\ @current_compile_env) :: Domain.t do
    gear_name_replaced = to_string(gear_name) |> String.replace("_", "-")
    base_domain =
      case Keyword.get(@deployments, env) do
        nil    -> System.get_env("BASE_DOMAIN") || "localhost"
        domain -> domain
      end
    "#{gear_name_replaced}.#{base_domain}"
  end
end
