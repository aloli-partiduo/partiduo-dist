# SPDX-License-Identifier: AGPL-3.0-or-later

# Programme d'une instance Partiduo, serveur HTTP ET ligne de commande, en un
# seul binaire (D-PKG-011) : lancé sous le nom `partiduo-manage` (lien posé
# par le paquet), c'est la ligne de commande Marten (migrate, provision,
# collectassets, instance…, comme `manage.cr`) ; sous tout autre nom
# (`partiduo-server`), le serveur HTTP. Compiler deux binaires recompilait
# deux fois toute l'application (plus d'une heure et ~47 Go chacun en
# `--release`, octobre 2026).
#
# Serveur : réglages de production de `partiduo-ui-bulma`
# (MARTEN_SECRET_KEY, MARTEN_ALLOWED_HOSTS, DATABASE_URL…), plus les
# applications des extensions. Avec `PARTIDUO_DEMO=1`, sert un dossier de
# démonstration déjà chargé (base dont le nom contient « demo », services
# externes simulés).
require "./partiduo-dist"
require "../config/settings/base"
require "../config/settings/**"
require "./cli"
require "./demo"
require "./demo/command"

if File.basename(PROGRAM_NAME) == "partiduo-manage"
  Marten.setup
  Marten::CLI.run
elsif PartiduoDist::Demo::Server.enabled?
  PartiduoDist::Demo::Server.start
else
  Marten.start
end
