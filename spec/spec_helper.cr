# SPDX-License-Identifier: AGPL-3.0-or-later

ENV["MARTEN_ENV"] = "test"

require "spec"

# Composition complète de la distribution (cœur, interface, toutes les
# extensions), migrations et dossiers de démonstration ; réglages de test de
# l'interface (DATABASE_URL, dont le nom doit contenir « test »).
require "../src/partiduo-dist"
require "../config/settings/base"
require "../config/settings/**"
require "../src/cli"
require "../src/demo"

require "marten/spec"
require "marten_auth/spec"

# Comptes, navigateur et contrôle des traductions de l'interface.
require "../lib/partiduo-ui-bulma/spec/support/accounts"
require "../lib/partiduo-ui-bulma/spec/support/browser"
require "../lib/partiduo-ui-bulma/spec/support/rate_limit"
require "../lib/partiduo-ui-bulma/spec/support/translations"

require "./support/**"
