# SPDX-License-Identifier: AGPL-3.0-or-later

# Composition de la distribution de production : le cœur et l'interface (réglages de
# `partiduo-ui-bulma`, déjà appliqués à son chargement), puis les
# applications Marten de chaque extension et de son interface.
Marten.configure do |config|
  config.installed_apps = config.installed_apps +
                          Document::INSTALLED_APPS + Document::Ui::INSTALLED_APPS +
                          Einvoicing::INSTALLED_APPS + Einvoicing::Ui::INSTALLED_APPS +
                          Superpdp::INSTALLED_APPS + Superpdp::Ui::INSTALLED_APPS +
                          Esalink::INSTALLED_APPS + Esalink::Ui::INSTALLED_APPS +
                          Choruspro::INSTALLED_APPS + Choruspro::Ui::INSTALLED_APPS +
                          Teledec::INSTALLED_APPS + Teledec::Ui::INSTALLED_APPS +
                          Urssaf::INSTALLED_APPS + Urssaf::Ui::INSTALLED_APPS +
                          Crm::INSTALLED_APPS + Crm::Ui::INSTALLED_APPS +
                          Modeles::INSTALLED_APPS + Modeles::Ui::INSTALLED_APPS +
                          Bankimport::INSTALLED_APPS + Bankimport::Ui::INSTALLED_APPS +
                          Amortis::INSTALLED_APPS + Amortis::Ui::INSTALLED_APPS
end
