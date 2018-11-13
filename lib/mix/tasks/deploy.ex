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

  # Location under build directory
  @template_output_dir "mix_deploy_local"

  @spec run(OptionParser.argv()) :: no_return
  def run(args) do
    # IO.puts (inspect args)
    config = parse_args(args)
    deploy_release(config)
  end

  @spec deploy_release(Keyword.t) :: no_return
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
    opts = [
      strict: [
        version: :string,
      ]
    ]
    {overrides, _} = OptionParser.parse!(argv, opts)

    mix_config = Mix.Project.config()
    user_config = mix_config[:mix_deploy_local] || []

    app_name = mix_config[:app]
    ext_name = app_name
               |> to_string
               |> String.replace("_", "-")

    base_path = user_config[:base_path] || "/srv"

    build_path = Mix.Project.build_path()

    defaults = [
      mix_env: Mix.env(),
      env_lang: "en_US.UTF-8",
      app_name: app_name,
      # Name of service files and directories
      ext_name: ext_name,
      version: mix_config[:version],
      # Base directory on target system
      base_path: base_path,
      # Directory where release will be extracted on target
      deploy_path: "#{base_path}/#{ext_name}",
      runtime_path: "/run/#{ext_name}",
      build_path: build_path,
      template_output_path: Path.join(build_path, @template_output_dir),
      deploy_user: "deploy",

      # App uses conform
      conform: false,
      conform_conf_path: "/etc/#{ext_name}/#{app_name}.conf",

      # App uses mix_systemd
      systemd: false,

      # Create /etc/suders.d config file allowing deploy or app user to restart
      sudo_deploy: false,
      sudo_app: false,

      exec: false,

      # These directories may be automatically created by newer versions of
      # systemd, otherwise we need to create them if necessary

      create_conf_dir: false,
      # conf_dir: default :ext_name
      # conf_path: default /etc/:conf_dir
      create_logs_dir: false,
      # log_dir: default :ext_name
      # log_path: default /var/log/:conf_dir
      create_tmp_dir: false,
      # tmp_dir: default :ext_name
      # tmp_path: default /var/tmp/:tmp_dir
      create_state_dir: false,
      # state_dir: default :ext_name
      # state_path: default /var/lib/:state_dir
      create_cache_dir: false,
      # cache_dir: default :ext_name
      # cache_path: default /var/lib/:cache_dir
      create_runtime_dir: false,
      # runtime_dir: default :ext_name
      # runtime_path: default /run/:runtime_dir

      restart_method: :systemd_flag, # :systemd_flag | :systemctl | :touch
    ]
    config = defaults
             |> Keyword.merge(user_config)
             |> Keyword.merge(overrides)

    Keyword.merge(config, [
      releases_path: Path.join(config[:deploy_path], "releases"),
      scripts_path: Path.join(config[:deploy_path], "scripts"),
      flags_path: Path.join(config[:deploy_path], "flags"),
      current_path: Path.join(config[:deploy_path], "current"),
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
    current_path = config[:current_path]
    IO.puts "Making link from #{release_path} to #{current_path}"
    remove_link(current_path)
    File.ln_s(release_path, current_path)
  end
  def rollback(dirs, _config) do
    IO.puts "Nothing to roll back to: releases = #{inspect dirs}"
  end

  def remove_link(current_path) do
    case File.read_link(current_path) do
      {:ok, target} ->
        IO.puts "Removing link from #{target} to #{current_path}"
        :ok = File.rm(current_path)
      {:error, _reason} ->
        IO.puts "No current link #{current_path}"
    end
  end

end

defmodule Mix.Tasks.Deploy.Local.Init do
  @shortdoc "Create directory structure and files for local deploy"

  @moduledoc "Create directory structure and files for local deploy."

  use Mix.Task

  @template_override_dir "mix_deploy_local"
  @app :mix_deploy_local

  def run(args) do
    config = Mix.Tasks.Deploy.Local.parse_args(args)

    ext_name = config[:ext_name]

    deploy_user = config[:deploy_user]
    # deploy_group = config[:deploy_group] || deploy_user
    app_user = config[:app_user] || deploy_user
    app_group = config[:app_group] || app_user

    {:ok, %{uid: deploy_uid}} = get_user_info(deploy_user)
    # {:ok, %{gid: deploy_gid}} = get_group_info(deploy_group)
    {:ok, %{uid: app_uid}} = get_user_info(app_user)
    {:ok, %{gid: app_gid}} = get_group_info(app_group)

    create_dir(config, config[:deploy_path],   deploy_uid, app_gid, 0o750)
    create_dir(config, config[:releases_path], deploy_uid, app_gid, 0o750)
    create_dir(config, config[:scripts_path],  deploy_uid, app_gid, 0o750)
    create_dir(config, config[:flags_path],    deploy_uid, app_gid, 0o770) # check perms

    maybe_create_dir(config, :create_conf_dir, :conf_dir, :conf_path, "/etc", deploy_uid, app_gid, 0o750)
    maybe_create_dir(config, :create_logs_dir, :logs_dir, :logs_path, "/var/log", app_uid, app_gid, 0o700)
    maybe_create_dir(config, :create_tmp_dir, :tmp_dir, :tmp_path, "/var/tmp", app_uid, app_gid, 0o700)
    maybe_create_dir(config, :create_state_dir, :state_dir, :state_path, "/var/lib", app_uid, app_gid, 0o700)
    maybe_create_dir(config, :create_cache_dir, :cache_dir, :cache_path, "/var/cache", app_uid, app_gid, 0o700)
    maybe_create_dir(config, :create_runtime_dir, :runtime_dir, :runtime_path, "/run", app_uid, app_gid, 0o750)

    copy_template(config, config[:scripts_path], "remote_console.sh", deploy_uid, app_gid, 0o750)

    if config[:systemd] do
      # Copy systemd files
      systemd_src_dir = Path.join(config[:build_path], "systemd/lib/systemd/system")
      {:ok, files} = File.ls(systemd_src_dir)
      for file <- files do
        src_path = Path.join(systemd_src_dir, file)
        dst_path = Path.join("/lib/systemd/system", file)
        Mix.shell.info "# Copying systemd unit from #{src_path} to #{dst_path}"
        :ok = copy_file(config, src_path, dst_path)
        own_file(config, dst_path, 0, 0, 0o644)
        if config[:exec] do
          {_, 0} = System.cmd("systemctl", ["enable", file])
        else
          Mix.shell.info "systemctl enable #{file}"
        end
      end
    end

    if config[:sudo_deploy] or config[:sudo_app] do
      copy_template(config, "/etc/sudoers.d", ext_name, "sudoers", 0, 0, 0o600)
    end
  end

  def copy_template(config, path, template, uid, gid, mode) do
    copy_template(config, path, template, template, uid, gid, mode)
  end

  def copy_template(config, path, template, file, uid, gid, mode) do
    output_dir = Path.join(config[:template_output_path], path)
    output_file = Path.join(output_dir, file)
    target_file = Path.join(path, file)

    Mix.shell.info "# Creating file #{target_file} from template #{template}"
    write_template(config, output_dir, file, template)
    :ok = copy_file(config, output_file, target_file)
    own_file(config, target_file, uid, gid, mode)
  end

  @spec copy_file(Keyword.t, Path.t, Path.t) :: :ok
  def copy_file(config, src_path, dst_path) do
    if config[:exec] do
      File.cp(src_path, dst_path)
    else
      Mix.shell.info "cp #{src_path} #{dst_path}"
      :ok
    end
  end

  @spec get_user_info(binary) :: map | :error
  def get_user_info(name) do
    {:ok, record} = get_passwd(:os.type(), name)
    # "jake:x:1003:1005:ansible-jake:/home/jake:/bin/bash\n"
    [name, pw, uid, gid, gecos, home, shell] = String.split(String.trim(record), ":")
    {:ok, %{
      user: name,
      password: pw,
      uid: String.to_integer(uid),
      gid: String.to_integer(gid),
      gecos: gecos,
      home: home,
      shell: shell
    }}
  end

  @spec get_group_info(binary) :: map | :error
  def get_group_info(name) do
    {:ok, record} = get_group(:os.type(), name)
    # "wheel:x:10:jake,foo\n"
    [name, pw, gid, member_bin] = String.split(String.trim(record), ":")
    members = case member_bin do
      "" -> []
      _ -> String.split(member_bin, ",")
    end
    {:ok, %{name: name, password: pw, gid: String.to_integer(gid), members: members}}
  end

  def get_passwd({:unix, :linux}, name) do
    {data, 0} = System.cmd("getent", ["passwd", name])
    {:ok, data}
  end
  def get_passwd({:unix, :darwin}, name) do
    path = "/Users/#{name}"
    values = for key <- ["UniqueID", "PrimaryGroupID", "RealName", "NFSHomeDirectory", "UserShell"] do
      {:ok, value} = dscl_read(path, key)
      value
    end 
    {:ok, Enum.join([name, "x"] ++ values, ":") <> "\n"}
  end

  def get_group({:unix, :linux}, name) do
    {data, 0} = System.cmd("getent", ["group", name])
    {:ok, data}
  end
  def get_group({:unix, :darwin}, name) do
    path = "/Groups/#{name}"
    {:ok, gid} = dscl_read(path, "PrimaryGroupID")
    {:ok, members_bin} = dscl_read(path, "GroupMembership")

    members = case members_bin do
      "" ->
        ""
      _ ->
        Enum.join(Regex.split(~r/\s+/, String.trim(members_bin), trim: true), ",")
    end
    {:ok, Enum.join([name, "x", gid, members], ":") <> "\n"}
  end

  @spec dscl_read(binary, binary) :: binary
  def dscl_read(path, key) do
    case System.cmd("dscl", ["-q", ".", "-read", path, key]) do
      {data, 0} -> 
        [key, value] = Regex.split(~r/\s+/, String.trim(data), multiline: true, parts: 2)
        {:ok, value}
      _ ->
        {:error, :not_found}
    end
  end

  @spec create_dir(Keyword.t, Path.t, non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  def create_dir(config, path, uid, gid, mode) do
    Mix.shell.info "# Creating dir #{path}"
    if config[:exec] do
      :ok = File.mkdir_p(path)
    else
      Mix.shell.info "mkdir -p #{path}"
    end
    own_file(config, path, uid, gid, mode)
  end

  @spec maybe_create_dir(Keyword.t, atom, atom, atom, String.t, non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  def maybe_create_dir(config, test_key, dir_key, path_key, default_prefix, uid, gid, mode) do
    if config[test_key] do
      dir = config[dir_key] || config[:ext_name]
      path = config[path_key] || Path.join(default_prefix, dir)
      Mix.shell.info "# Creating dir #{path}"
      create_dir(config, path, uid, gid, mode)
    end
  end

  @spec own_file(Keyword.t, Path.t, non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  def own_file(config, path, uid, gid, mode) do
    if config[:exec] do
      :ok = File.chown(path, uid)
      :ok = File.chgrp(path, gid)
      :ok = File.chmod(path, mode)
    else
      Mix.shell.info "chown #{uid}:#{gid} #{path}"
      Mix.shell.info "chmod #{Integer.to_string(mode, 8)} #{path}"
    end
  end

  @spec write_template(Keyword.t, Path.t, String.t) :: :ok
  def write_template(config, target_path, template) do
    write_template(config, target_path, template, template)
  end

  @spec write_template(Keyword.t, Path.t, String.t, Path.t) :: :ok
  def write_template(config, target_path, template, filename) do
    :ok = File.mkdir_p(target_path)
    {:ok, data} = template_name(template, config)
    :ok = File.write(Path.join(target_path, filename), data)
  end

  @spec template_name(Path.t, Keyword.t) :: {:ok, String.t} | {:error, term}
  def template_name(name, params \\ []) do
    template_name = "#{name}.eex"
    template_path = params[:template_path] || @template_override_dir
    override_path = Path.join([template_path, template_name])
    if File.exists?(override_path) do
      template_path(override_path)
    else
      Application.app_dir(@app, Path.join("priv", "templates"))
      |> Path.join(template_name)
      |> template_path(params)
    end
  end

  @doc "Eval template with params"
  @spec template_path(String.t, Keyword.t) :: {:ok, String.t} | {:error, term}
  def template_path(template_path, params \\ []) do
    {:ok, EEx.eval_file(template_path, params, [trim: true])}
  rescue
    e ->
      {:error, {:template, e}}
  end

end
