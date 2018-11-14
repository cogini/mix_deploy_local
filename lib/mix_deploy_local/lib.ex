defmodule MixDeployLocal.Lib do
  @moduledoc "Utility functions"

  @app :mix_deploy_local

  @spec copy_file(boolean, Path.t, Path.t) :: :ok | {:error, :file.posix()}
  def copy_file(true, src_path, dst_path) do
    File.cp(src_path, dst_path)
  end
  def copy_file(_, src_path, dst_path) do
    Mix.shell.info "cp #{src_path} #{dst_path}"
    :ok
  end

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

  def enable_systemd_unit(true, name) do
    {_, 0} = System.cmd("systemctl", ["enable", name])
  end
  def enable_systemd_unit(_, name) do
    Mix.shell.info "systemctl enable #{name}"
  end

  @doc "Generate file from template to build_path, then copy to target"
  @spec copy_template(boolean, Keyword.t, Path.t, Path.t, String.t, non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  def copy_template(exec, vars, dest, path, template, uid, gid, mode) do
    copy_template(exec, vars, dest, path, template, template, uid, gid, mode)
  end

  @spec copy_template(boolean, Keyword.t, Path.t, Path.t, String.t, String.t, non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  def copy_template(exec, vars, dest, path, template, file, uid, gid, mode) do
    output_dir = Path.join(dest, path)
    output_file = Path.join(output_dir, file)
    target_file = Path.join(path, file)

    Mix.shell.info "# Creating file #{target_file} from template #{template}"
    :ok = File.mkdir_p(output_dir)
    {:ok, data} = template_name(template, vars)
    :ok = File.write(output_file, data)

    :ok = copy_file(exec, output_file, target_file)
    own_file(exec, target_file, uid, gid, mode)
  end

  @spec write_template(Keyword.t, Path.t, String.t) :: :ok
  def write_template(vars, target_path, template) do
    write_template(vars, target_path, template, template)
  end

  @spec write_template(Keyword.t, Path.t, String.t, Path.t) :: :ok
  def write_template(vars, target_path, template, filename) do
    target_file = Path.join(target_path, filename)
    :ok = File.mkdir_p(target_path)
    {:ok, data} = template_name(template, vars)
    :ok = File.write(target_file, data)
  end

  @spec template_name(Path.t, Keyword.t) :: {:ok, String.t} | {:error, term}
  def template_name(name, vars \\ []) do
    template_file = "#{name}.eex"
    override_file = Path.join(vars[:template_dir], template_file)
    if File.exists?(override_file) do
      template_file(override_file)
    else
      Application.app_dir(@app, ["priv", "templates"])
      |> Path.join(template_file)
      |> template_file(vars)
    end
  end

  @doc "Eval template with params"
  @spec template_file(String.t, Keyword.t) :: {:ok, String.t} | {:error, term}
  def template_file(template_file, params \\ []) do
    {:ok, EEx.eval_file(template_file, params, [trim: true])}
  rescue
    e ->
      {:error, {:template, e}}
  end

end
