defmodule Mix.Tasks.Deploy.Local do
  @shortdoc "Deploy release to local machine"

  @moduledoc """
  This task deploys a Distillery release to the local machine.

  It extracts the release tar to a timestamped directory like
  `/srv/:app/releases/20170619175601`, then makes a symlink
  from `/srv/:app/current` to it.

  This module looks for configuration in the mix project, to get the app and version,
  and under the application environment under `mix_deploy_local`.

  * `base_dir` sets the base directory, default `/srv`.
  * `deploy_dir` sets the target directory completely manually, ignoring `base_dir` and `app`.
  ```
  """

  use Mix.Task

  alias MixDeployLocal.User

  # Name of app, used to get info from application environment
  @app :mix_deploy_local

  # Name of directory under build directory where module stores generated files
  @output_dir "mix_deploy_local"

  # Name of directory where user can override templates
  @template_override_dir "mix_deploy_local"

  @spec run(OptionParser.argv()) :: no_return
  def run(args) do
    # IO.puts (inspect args)
    config = parse_args(args)
    deploy_release(config)
  end

  @spec deploy_release(Keyword.t) :: no_return
  def deploy_release(cfg) do
    release_dir = Path.join(cfg[:releases_dir], create_timestamp())
    Mix.shell.info "Deploying release to #{release_dir}"
    :ok = File.mkdir_p(release_dir)

    app = to_string(cfg[:app_name])
    tar_file = Path.join([cfg[:build_path], "rel", app, "releases", cfg[:version], "#{app}.tar.gz"])
    Mix.shell.info "Extracting tar #{tar_file}"
    :ok = :erl_tar.extract(to_charlist(tar_file), [{:cwd, release_dir}, :compressed])

    current_link = cfg[:current_path]
    if File.exists?(current_link) do
      :ok = File.rm(current_link)
    end
    :ok = File.ln_s(release_dir, current_link)
  end

  def create_timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.now_to_universal_time(:os.timestamp())
    timestamp = :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [year, month, day, hour, minute, second])
    timestamp |> List.flatten |> to_string
  end

  @spec parse_args(OptionParser.argv()) :: Keyword.t
  def parse_args(argv) do
    opts = [
      strict: [
        version: :string,
      ]
    ]
    {overrides, _} = OptionParser.parse!(argv, opts)

    mix_config = Mix.Project.config()
    user_config = Application.get_all_env(@app)

    app_name = mix_config[:app]
    ext_name = app_name
               |> to_string
               |> String.replace("_", "-")

    base_dir = user_config[:base_dir] || "/srv"

    build_path = Mix.Project.build_path()

    {{cur_user, _cur_uid}, {cur_group, _cur_gid}, _} = User.get_id()

    defaults = [
      mix_env: Mix.env(),

      # LANG environment var for running scripts
      env_lang: "en_US.UTF-8",

      # Elixir application name
      app_name: app_name,

      # Name of service files and directories
      ext_name: ext_name,

      # App version
      version: mix_config[:version],

      # Base directory on target system
      base_dir: base_dir,

      # Directory for release files on target
      deploy_dir: "#{base_dir}/#{ext_name}",

      # Mix build_path
      build_path: build_path,

      # Staging output directory for generated files
      output_dir: Path.join(build_path, @output_dir),

      # Directory with templates which override defaults
      template_dir: Path.join("templates", @template_override_dir),

      # OS user to own files and run app
      deploy_user: cur_user,
      deploy_group: cur_group,

      # Whether app uses conform
      conform: false,
      conform_conf_path: "/etc/#{ext_name}/#{app_name}.conf",

      # Whether app uses mix_systemd
      mix_systemd: false,
      # Target systemd version
      systemd_version: 219, # CentOS 7
      # systemd_version: 229, # Ubuntu 16.04

      # Whether to create /etc/suders.d file allowing deploy or app user to restart app
      sudo_deploy: false,
      sudo_app: false,

      # Execute priviliged commands to modify target system, otherwise generate shell commands
      exec_commands: false,

      # These directories may be automatically created by newer versions of
      # systemd, otherwise we need to create them the app uses them

      # We use runtime_dir as RELEASE_MUTABLE_DIR
      create_runtime_dir: true,
      runtime_dir_name: ext_name,
      runtime_dir_base: "/run",

      # Enable if using conform
      create_conf_dir: false,
      conf_dir_name: ext_name,
      conf_dir_base: "/etc",

      create_logs_dir: false,
      logs_dir_name: ext_name,
      logs_dir_base: "/var/log",

      create_tmp_dir: false,
      tmp_dir_name: ext_name,
      tmp_dir_base: "/var/tmp",

      create_state_dir: false,
      state_dir_name: ext_name,
      state_dir_base: "/var/lib",

      create_cache_dir: false,
      cache_dir_name: ext_name,
      cache_dir_base: "/var/cache",

      restart_method: :systemd_flag, # :systemd_flag | :systemctl | :touch
    ]

    cfg = defaults
             |> Keyword.merge(user_config)
             |> Keyword.merge(overrides)

    # Default OS user and group names
    cfg = Keyword.merge([
      app_user: cfg[:deploy_user],
      app_group: cfg[:deploy_group],
    ], cfg)

    cfg = Keyword.merge(cfg, [
      deploy_uid: cfg[:deploy_uid] || User.get_uid(cfg[:deploy_user]),
      deploy_gid: cfg[:deploy_gid] || User.get_gid(cfg[:deploy_group]),
      app_uid: cfg[:app_uid] || User.get_uid(cfg[:app_user]),
      app_gid: cfg[:app_gid] || User.get_gid(cfg[:app_group]),
    ])

    # Mix.shell.info "cfg: #{inspect cfg}"

    # Data calculated from other things
    Keyword.merge([
      releases_dir: Path.join(cfg[:deploy_dir], "releases"),
      scripts_dir: Path.join(cfg[:deploy_dir], "scripts"),
      flags_dir: Path.join(cfg[:deploy_dir], "flags"),
      current_dir: Path.join(cfg[:deploy_dir], "current"),

      runtime_dir: Path.join(cfg[:runtime_dir_base], cfg[:runtime_dir_name]),
      conf_dir: Path.join(cfg[:conf_dir_base], cfg[:conf_dir_name]),
      logs_dir: Path.join(cfg[:logs_dir_base], cfg[:logs_dir_name]),
      tmp_dir: Path.join(cfg[:tmp_dir_base], cfg[:tmp_dir_name]),
      state_dir: Path.join(cfg[:state_dir_base], cfg[:state_dir_name]),
      cache_dir: Path.join(cfg[:cache_dir_base], cfg[:cache_dir_name]),
    ], cfg)
  end

end

defmodule Mix.Tasks.Deploy.Local.Rollback do
  @moduledoc """
  Update current symlink to point to the previous release directory.
  """

  use Mix.Task

  def run(args) do
    cfg = Mix.Tasks.Deploy.Local.parse_args(args)

    dirs = cfg[:releases_path] |> File.ls! |> Enum.sort |> Enum.reverse

    rollback(dirs, cfg)
  end

  @spec rollback([Path.t], Keyword.t) :: :ok
  defp rollback([_current, prev | _rest], cfg) do
    release_path = Path.join(cfg[:releases_path], prev)
    current_dir = cfg[:current_dir]
    Mix.shell.info "Making link from #{release_path} to #{current_dir}"
    :ok = remove_link(current_dir)
    :ok = File.ln_s(release_path, current_dir)
  end
  defp rollback(dirs, _cfg) do
    Mix.shell.info "Nothing to roll back to: releases = #{inspect dirs}"
    :ok
  end

  @spec remove_link(Path.t) :: :ok | {:error, :file.posix()}
  defp remove_link(current_path) do
    case File.read_link(current_path) do
      {:ok, target} ->
        Mix.shell.info "Removing link from #{target} to #{current_path}"
        File.rm(current_path)
      {:error, _reason} ->
        Mix.shell.info "No current link #{current_path}"
        :ok
    end
  end
end

defmodule Mix.Tasks.Deploy.Local.Init do
  @moduledoc "Create directory structure and files for local deploy"

  use Mix.Task

  # Directory under build_path where mix_systemd keeps its files
  @mix_systemd_dir "systemd"

  import MixDeployLocal.Commands

  def run(args) do
    cfg = Mix.Tasks.Deploy.Local.parse_args(args)

    ext_name = cfg[:ext_name]
    exec = cfg[:exec_commands]

    deploy_user = {cfg[:deploy_user], cfg[:deploy_uid]}
    # deploy_group = {cfg[:deploy_group], cfg[:deploy_gid]}
    app_user = {cfg[:app_user], cfg[:app_uid]}
    app_group = {cfg[:app_group], cfg[:app_gid]}

    create_dir(exec, cfg[:deploy_dir],   deploy_user, app_group, 0o750)
    create_dir(exec, cfg[:releases_dir], deploy_user, app_group, 0o750)
    create_dir(exec, cfg[:scripts_dir],  deploy_user, app_group, 0o750)

    # Used to trigger restart when deploying a new release
    create_dir(exec, cfg[:flags_dir],    deploy_user, app_group, 0o750) # might need to be 0o770

    # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=

    # systemd will automatically create directories in newer versions
    if cfg[:systemd_version] < 235 do
      # We always need this, as we use it for RELEASE_MUTABLE_DIR
      create_dir(exec, cfg[:runtime_dir], app_user, app_group, 0o750)

      if cfg[:create_conf_dir] do
        create_dir(exec, cfg[:conf_dir], deploy_user, app_group, 0o750)
      end
      if cfg[:create_logs_dir] do
        create_dir(exec, cfg[:logs_dir], app_user, app_group, 0o700)
      end
      if cfg[:create_tmp_dir] do
        create_dir(exec, cfg[:tmp_dir], app_user, app_group, 0o700)
      end
      if cfg[:create_state_dir] do
        create_dir(exec, cfg[:state_dir], app_user, app_group, 0o700)
      end
      if cfg[:create_cache_dir] do
        create_dir(exec, cfg[:cache_dir], app_user, app_group, 0o700)
      end
    end

    copy_template(exec, cfg, cfg[:output_dir], cfg[:scripts_dir], "remote_console.sh", deploy_user, app_group, 0o750)

    # Copy systemd files
    if cfg[:mix_systemd] do
      systemd_src_dir = Path.join([cfg[:build_path], @mix_systemd_dir, "/lib/systemd/system"])
      {:ok, files} = File.ls(systemd_src_dir)
      for file <- files do
        src_file = Path.join(systemd_src_dir, file)
        dst_file = Path.join("/lib/systemd/system", file)
        Mix.shell.info "# Copying systemd unit from #{src_file} to #{dst_file}"
        :ok = copy_file(exec, src_file, dst_file)
        own_file(exec, dst_file, {"root", 0}, {"root", 0}, 0o644)
        enable_systemd_unit(exec, file)
      end
    end

    # Generate /etc/sudoers.d config
    if cfg[:sudo_deploy] or cfg[:sudo_app] do
      copy_template(exec, cfg, "/etc/sudoers.d", ext_name, "sudoers", {"root", 0}, {"root", 0}, 0o600)
    end
  end

end
