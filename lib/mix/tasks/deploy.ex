defmodule Mix.Tasks.Deploy.Local do
  @shortdoc "Deploy release to local machine"

  @moduledoc """
  This task deploys a Distillery release to the local machine.

  It extracts the release tar to a timestamped directory like
  `/srv/:app/releases/20170619175601`, then makes a symlink
  from `/srv/:app/current` to it.

  This module looks for configuration in the mix project under the
  `mix_deploy_local` key.

  * `base_path` sets the base directory, default `/srv`.
  * `deploy_path` sets the target directory completely manually, ignoring `base_path` and `app`.

  ```elixir
  def project do
  [
    app: :example_app,
    version: "0.1.0",
    elixir: "~> 1.6",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    mix_deploy_local: [
      deploy_path: "/my/special/place/myapp"
    ]
  ]
  end
  ```
  """

  use Mix.Task

  def run(args) do
    # IO.puts (inspect args)
    config = parse_args(args)
    deploy_release(config)
  end

  def deploy_release(config) do
    ts = create_timestamp()
    release_path = Path.join(config[:releases_path], ts)
    Mix.shell.info "Deploying release to #{release_path}"
    File.mkdir_p!(release_path)

    app = to_string(config[:app])
    tar_path = Path.join([config[:build_path], "rel", app, "releases", config[:version], "#{app}.tar.gz"])
    Mix.shell.info "Extracting tar #{tar_path}"
    :ok = :erl_tar.extract(tar_path, [{:cwd, release_path}, :compressed])

    current_link = config[:current_link]
    if File.exists?(current_link) do
      File.rm!(current_link)
    end
    File.ln_s(release_path, current_link)
  end

  def create_timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.now_to_universal_time(:os.timestamp())
    timestamp = :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [year, month, day, hour, minute, second])
    timestamp |> List.flatten |> to_string
  end

  def parse_args(argv) do
    {_args, _, _} = OptionParser.parse(argv)
    mix_config = Mix.Project.config()
    user_config = mix_config[:config] || []

    ext_name = mix_config[:app]
               |> to_string
               |> String.replace("_", "-")

    base_path = user_config[:base_path] || "/srv"

    defaults = [
      app: mix_config[:app],
      ext_name: ext_name,
      version: mix_config[:version],
      base_path: base_path,
      deploy_path: "#{base_path}/#{ext_name}",
      build_path: Mix.Project.build_path(),
    ]
    config = Keyword.merge(defaults, user_config)

    Keyword.merge(config, [
      releases_path: Path.join(config[:deploy_path], "releases"),
      current_link: Path.join(config[:deploy_path], "current"),
    ])
  end

end

defmodule Mix.Tasks.Deploy.Local.Rollback do
  @shortdoc "Roll back to previous release"

  @moduledoc """
  Update current symlink to point to the previous release directory.
  """

  use Mix.Task

  def run(args) do
    config = Mix.Tasks.Deploy.Local.parse_args(args)

    dirs = config[:releases_path] |> File.ls! |> Enum.sort |> Enum.reverse

    rollback(dirs, config)
  end

  def rollback([_current, prev | _rest], config) do
    release_path = Path.join(config[:releases_path], prev)
    IO.puts "Making link from #{release_path} to #{config[:current_link]}"
    remove_link(config[:current_link])
    File.ln_s(release_path, config[:current_link])
  end
  def rollback(dirs, _config) do
    IO.puts "Nothing to roll back to: releases = #{inspect dirs}"
  end

  def remove_link(current_link) do
    case File.read_link(current_link) do
      {:ok, target} ->
        IO.puts "Removing link from #{target} to #{current_link}"
        :ok = File.rm(current_link)
      {:error, _reason} ->
        IO.puts "No current link #{current_link}"
    end
  end

end

defmodule Mix.Tasks.Deploy.Local.Init do
  @shortdoc "Create directory structure for local deploy"

  @moduledoc """
  Create directory structure for local deploy.
  """

  use Mix.Task

  def run(args) do
    config = Mix.Tasks.Deploy.Local.parse_args(args)
    File.mkdir_p!(config[:base_dir])
  end

end
