# SPDX-License-Identifier: AGPL-3.0-or-later

# Démonstration : chargement et vérification des dossiers fictifs décrits par
# les fichiers de données de `partiduo-demo` (commande `partiduo-manage
# demo`, `src/demo/command.cr`, requise par `manage.cr` et `src/server.cr`),
# services externes simulés et serveur de démonstration (`PARTIDUO_DEMO=1`).
# Inactif dans une instance réelle.
require "./demo/support"
require "./demo/dates"
require "./demo/format"
require "./demo/images"
require "./demo/ubl"
require "./demo/simulators"
require "./demo/dossier"
require "./demo/agenda"
require "./demo/loader"
require "./demo/loader/*"
require "./demo/verifier"
require "./demo/server"
