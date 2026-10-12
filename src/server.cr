# SPDX-License-Identifier: AGPL-3.0-or-later

# Serveur HTTP d'une instance Partiduo : binaire `partiduo-server`. Réglages
# de production de `partiduo-ui-bulma` (MARTEN_SECRET_KEY,
# MARTEN_ALLOWED_HOSTS, DATABASE_URL…), plus les applications des extensions.
# Avec `PARTIDUO_DEMO=1`, sert un dossier de démonstration déjà chargé
# (base dont le nom contient « demo », services externes simulés).
require "./partiduo-dist"
require "../config/settings/base"
require "../config/settings/**"
require "./demo"

if PartiduoDist::Demo::Server.enabled?
  PartiduoDist::Demo::Server.start
else
  Marten.start
end
