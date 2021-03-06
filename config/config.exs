# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :mix_deploy_local, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:mix_deploy_local, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#
# config :mix_deploy_local,
#   deploy_group: "staff"

config :mix_deploy_local,
  deploy_group: "staff",
  sudo_deploy: true,
  sudo_app: true

# config :mix_deploy_local,
#   deploy_user: "deploy",
#   deploy_group: "deploy",
#   app_user: "foo",
#   app_group: "foo",
#   deploy_uid: 1003,
#   deploy_gid: 1005,
#   app_uid: 1006,
#   app_gid: 1007

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"
