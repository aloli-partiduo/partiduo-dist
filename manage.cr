# SPDX-License-Identifier: AGPL-3.0-or-later

# Ligne de commande Marten de la distribution : binaire `partiduo-manage`
# (`migrate`, `provision`, `collectassets`, `demo`…), ou
# `crystal run manage.cr --`.
require "./src/partiduo-dist"
require "./config/settings/base"
require "./config/settings/**"
require "./src/cli"
require "./src/demo"
require "./src/demo/command"

Marten.setup
Marten::CLI.run
