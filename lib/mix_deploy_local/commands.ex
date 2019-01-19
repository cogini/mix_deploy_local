defmodule MixDeployLocal.Commands do
  @moduledoc """
  Deployment commands.

  These functions perform deployment functions like copying files and generating output files from templates.

  Because deployment requres elevated permissions, instead of executing the
  commands, they can optionally output the shell equivalents. You can capture
  this in a shell script which you run under sudo.
  """

  alias MixDeployLocal.Templates

  @typep name_id() :: {String.t, non_neg_integer}

  @doc "Copy file"
  @spec copy_file(boolean, Path.t, Path.t) :: :ok | {:error, :file.posix()}
  def copy_file(true, src_path, dst_path) do
    File.cp(src_path, dst_path)
  end
  def copy_file(_, src_path, dst_path) do
    Mix.shell.info "cp #{src_path} #{dst_path}"
    :ok
  end

  @doc "Create directory"
  @spec create_dir(boolean, Path.t, {binary, non_neg_integer}, {binary, non_neg_integer}, non_neg_integer) :: :ok
  def create_dir(true, path, uid, gid, mode) do
    Mix.shell.info "# Creating dir #{path}"
    :ok = File.mkdir_p(path)
    own_file(true, path, uid, gid, mode)
  end
  def create_dir(_, path, uid, gid, mode) do
    Mix.shell.info "# Creating dir #{path}"
    Mix.shell.info "mkdir -p #{path}"
    own_file(false, path, uid, gid, mode)
  end

  @doc "Set file ownership and permissions"
  @spec own_file(boolean, Path.t, {binary, non_neg_integer}, {binary, non_neg_integer}, non_neg_integer) :: :ok
  def own_file(true, path, {_user, uid}, {_group, gid}, mode) do
    :ok = File.chown(path, uid)
    :ok = File.chgrp(path, gid)
    :ok = File.chmod(path, mode)
  end
  def own_file(_, path, {user, _uid}, {group, _gid}, mode) do
    Mix.shell.info "chown #{user}:#{group} #{path}"
    Mix.shell.info "chmod #{Integer.to_string(mode, 8)} #{path}"
  end

  @doc "Enable systemd unit"
  @spec enable_systemd_unit(boolean, String.t) :: :ok
  def enable_systemd_unit(true, name) do
    {_, 0} = System.cmd("systemctl", ["enable", name])
    :ok
  end
  def enable_systemd_unit(_, name) do
    Mix.shell.info "systemctl enable #{name}"
    :ok
  end

  @doc "Generate file from template to build_path, then copy to target"
  @spec copy_template(boolean, Keyword.t, Path.t, Path.t, String.t, name_id(), name_id(), non_neg_integer) :: :ok
  def copy_template(exec, vars, dest, path, template, user, group, mode) do
    copy_template(exec, vars, dest, path, template, template, user, group, mode)
  end

  @spec copy_template(boolean, Keyword.t, Path.t, Path.t, String.t, String.t, name_id(), name_id(), non_neg_integer) :: :ok
  def copy_template(exec, vars, dest, path, template, file, user, group, mode) do
    output_dir = Path.join(dest, path)
    output_file = Path.join(output_dir, file)
    target_file = Path.join(path, file)

    Mix.shell.info "# Creating file #{target_file} from template #{template}"
    :ok = File.mkdir_p(output_dir)
    {:ok, data} = Templates.template_name(template, vars)
    :ok = File.write(output_file, data)

    :ok = copy_file(exec, output_file, target_file)
    own_file(exec, target_file, user, group, mode)
  end
end
