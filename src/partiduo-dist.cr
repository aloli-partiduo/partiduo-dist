# SPDX-License-Identifier: AGPL-3.0-or-later

# Composition de la distribution de production : l'interface Bulma (qui
# charge le cœur), puis chaque extension et son interface. L'ordre suit les
# dépendances entre extensions (EINV après DOCUMENT, SUPERPDP et ESALINK
# après EINV). Les réglages (`config/settings/`) ajoutent leurs
# applications Marten.
require "partiduo-ui-bulma/partiduo_ui"
require "partiduo-document"
require "partiduo-document/ui/bulma"
require "partiduo-einvoicing"
require "partiduo-einvoicing/ui/bulma"
require "partiduo-superpdp"
require "partiduo-superpdp/ui/bulma"
require "partiduo-esalink"
require "partiduo-esalink/ui/bulma"
require "partiduo-choruspro"
require "partiduo-choruspro/ui/bulma"
require "partiduo-teledec"
require "partiduo-teledec/ui/bulma"
require "partiduo-urssaf"
require "partiduo-urssaf/ui/bulma"
require "partiduo-crm"
require "partiduo-crm/ui/bulma"
require "partiduo-modeles"
require "partiduo-modeles/ui/bulma"
require "partiduo-bankimport"
require "partiduo-bankimport/ui/bulma"
require "partiduo-amortis"
require "partiduo-amortis/ui/bulma"
require "partiduo-sepa"
require "partiduo-sepa/ui/bulma"
require "partiduo-reports"
require "partiduo-reports/ui/bulma"
require "partiduo-import"
require "partiduo-import/ui/bulma"
require "partiduo-form"
require "partiduo-form/ui/bulma"

# Version de la distribution de production.
module PartiduoDist
  # Lue à la compilation dans `shard.yml`, seule source du numéro : chaque
  # commit y incrémente le dernier chiffre.
  VERSION = {{
              (read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}
end
