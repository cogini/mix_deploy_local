defmodule MixDeployLocal.Os do
  @moduledoc "OS interface functions"

  @doc "Get OS user info from /etc/passwd"
  @spec get_user_info(String.t) :: map | :error
  def get_user_info(name) do
    {:ok, record} = get_passwd_record(:os.type(), name)
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

  @doc "Get OS group info from /etc/group"
  @spec get_group_info(String.t) :: map | :error
  def get_group_info(name) do
    {:ok, record} = get_group_record(:os.type(), name)
    # "wheel:x:10:jake,foo\n"
    [name, pw, gid, members] = String.split(String.trim(record), ":")
    members = parse_group_members(members)
    {:ok, %{name: name, password: pw, gid: String.to_integer(gid), members: members}}
  end

  @spec get_passwd_record({atom, atom}, String.t) :: {:ok, String.t}
  def get_passwd_record({:unix, :linux}, name) do
    {data, 0} = System.cmd("getent", ["passwd", name])
    {:ok, data}
  end
  def get_passwd_record({:unix, :darwin}, name) do
    path = "/Users/#{name}"
    values = for key <- ["UniqueID", "PrimaryGroupID", "RealName", "NFSHomeDirectory", "UserShell"] do
      {:ok, value} = dscl_read(path, key)
      value
    end
    {:ok, Enum.join([name, "x"] ++ values, ":") <> "\n"}
  end

  @spec get_group_record({atom, atom}, String.t) :: {:ok, String.t}
  def get_group_record({:unix, :linux}, name) do
    {record, 0} = System.cmd("getent", ["group", name])
    {:ok, record}
  end
  def get_group_record({:unix, :darwin}, name) do
    path = "/Groups/#{name}"
    {:ok, gid} = dscl_read(path, "PrimaryGroupID")
    {:ok, members} = dscl_read(path, "GroupMembership")
    members = dscl_format_group_members(members)
    record = Enum.join([name, "x", gid, members], ":") <> "\n"
    {:ok, record}
  end

  @spec dscl_read(String.t, String.t) :: {:ok, String.t} | {:error, :not_found}
  def dscl_read(path, key) do
    case System.cmd("dscl", ["-q", ".", "-read", path, key]) do
      {data, 0} ->
        [_key, value] = Regex.split(~r/\s+/, String.trim(data), multiline: true, parts: 2)
        {:ok, value}
      _ ->
        {:error, :not_found}
    end
  end

  @spec dscl_format_group_members(String.t) :: String.t
  defp dscl_format_group_members(""), do: ""
  defp dscl_format_group_members(members) do
    Enum.join(Regex.split(~r/\s+/, String.trim(members), trim: true), ",")
  end

  @spec parse_group_members(String.t) :: [String.t]
  defp parse_group_members(""), do: []
  defp parse_group_members(members), do: String.split(members, ",")

end
