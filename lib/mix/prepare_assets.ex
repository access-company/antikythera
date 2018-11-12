# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Mix.Tasks.Antikythera.PrepareAssets do
  @shortdoc "Prepares static assets for your gear"
  @moduledoc """
  #{@shortdoc}.

  This mix task is called right before compilations of the gear in antikythera's auto-deploy script.
  It ensures all static assets of your gear reside in `priv/static/` directory before compilations of `YourGear.Asset` module.
  Assets in `priv/static/` directory will then be uploaded to cloud storage for serving via CDN.
  See `Antikythera.Asset` for details.

  If your gear uses some kind of preprocessing tools to generate asset files (JS, CSS, etc.),
  you have to set up the supported asset preparation method described in the next section.

  Normally you do not have to invoke this mix task when you locally develop your assets.
  Though you may do so in order to confirm asset preparation is working as you intended.

  This mix task invokes the preprocessing tools with `ANTIKYTHERA_COMPILE_ENV` environment variable
  (see also `Antikythera.Env`).
  You can use this environment variable to distinguish for which environment current script is running.

  ## Supported Asset Preparation Method

  Asset preparation process is split into two steps: package installation step and build step.
  If any part of the preparation process resulted in failure (non-zero exit code),
  the whole task will abort and thus auto-deploy will fail.

  - Prerequisite: `package.json` file and `antikythera_prepare_assets` script in it

  Note that if the above prerequisite is not present,
  **the whole asset preparation process will be skipped** since package installation is unnecessary.

  ### Package Installation

  Use [`yarn`](https://yarnpkg.com/en/) if `yarn.lock` file exists, otherwise use `npm install`.

  ### Build using [npm-scripts](https://docs.npmjs.com/misc/scripts)

  - Command: `npm run antikythera_prepare_assets`
  - Within `antikythera_prepare_assets` script, you may execute any asset-related actions such as:
      - Linting
      - Type Checking
      - Testing
      - Compiling/Transpiling
      - Uglifying/Minifying
      - etc...
  - How to organize these actions is up to you. You may use whatever tools available in `npm`,
    such as [`webpack`](https://webpack.js.org/) or [`browserify`](http://browserify.org/).

  #### Note on implementation

  This step is responsible for placing finalized static assets into `priv/static/` directory.

  In old versions of `gear_generator`, Node.js packages that depend on
  [`compass`](http://compass-style.org/) was used by default in generated gear.
  `compass` gem was (and is) globally installed on antikythera jenkins server to enable them.

  However, [`compass` is no longer maintained](https://github.com/Compass/compass/commit/dd74a1cfef478a896d03152b2c2a3b93839d168e).
  We recommend you to consider using alternative SASS/SCSS processor.
  `compass` gem will be kept installed for backward compatibility.
  """

  use Mix.Task
  alias Antikythera.Asset

  @impl true
  def run(args) do
    run_impl(List.first(args) || "undefined")
  end

  defp run_impl(env) do
    if npm_script_available?(env) do
      install_packages!(env)
      build_assets!(env)
      dump_asset_file_paths()
    else
      IO.puts("Skipping. Asset preparation is not configured.")
      IO.puts("Define `antikythera_prepare_assets` npm-script if you want antikythera to prepare assets for your gear.")
    end
  end

  defp npm_script_available?(env) do
    run_command!("npm", ["run"], env)
    |> String.split("\n", trim: true)
    |> Enum.member?("  antikythera_prepare_assets")
  end

  defp install_packages!(env) do
    if File.exists?("yarn.lock") do
      run_command!("yarn", [], env)
    else
      remove_node_modules_if_dependencies_changed!()
      run_command!("npm", ["install"], env)
    end
  end

  defp remove_node_modules_if_dependencies_changed!() do
    case System.get_env("GIT_PREVIOUS_SUCCESSFUL_COMMIT") do
      nil ->
        :ok
      commit ->
        files_to_check = ["package.json", "npm-shrinkwrap.json", "package-lock.json"]
        {_output, status} = System.cmd("git", ["diff", "--quiet", commit, "--" | files_to_check])
        if status == 1 do
          IO.puts("Removing node_modules/ in order to avoid potential issues in npm's dependency resolution.")
          File.rm_rf!("node_modules")
        end
    end
  end

  defp build_assets!(env) do
    run_command!("npm", ["run", "antikythera_prepare_assets"], env)
  end

  def dump_asset_file_paths() do
    IO.puts("Done. Current assets under priv/static/ directory:")
    case Asset.list_asset_file_paths() do
      []    -> IO.puts("  (No asset files exist)")
      paths -> Enum.each(paths, fn path -> IO.puts("  * " <> path) end)
    end
  end

  defun run_command!(cmd :: v[String.t], args :: v[[String.t]], env :: v[String.t]) :: String.t do
    invocation = Enum.join([cmd | args], " ")
    IO.puts("$ #{invocation}")
    {output, status} = System.cmd(cmd, args, [stderr_to_stdout: true, env: %{"ANTIKYTHERA_COMPILE_ENV" => env}])
    IO.puts(output)
    if status == 0 do
      output
    else
      raise("`#{invocation}` resulted in non-zero exit code: #{status}")
    end
  end
end
