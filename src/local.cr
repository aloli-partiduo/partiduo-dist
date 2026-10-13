# SPDX-License-Identifier: AGPL-3.0-or-later

# Commande `partiduo` : dossiers sur le poste de leur utilisateur, sans
# serveur (création, ouverture, fermeture, liste, suppression). Elle pilote
# `partiduo-manage` et `partiduo-server`, installés à côté d'elle ; elle ne
# charge pas l'application et se construit seule
# (`shards build partiduo`).
require "./local/cli"

exit PartiduoDist::Local::CLI.run(ARGV)
