# SPDX-License-Identifier: AGPL-3.0-or-later

require "./spec_helper"

# Traductions de toutes les pages de la distribution (ADR-005 D7) : le cœur,
# l'interface et les écrans de toutes les extensions composées, chaque
# route du routeur de Marten (montages des extensions compris) servie en
# `GET`, obtenue en fr, en et nl par un administrateur, sur les dossiers de
# démonstration de `partiduo-demo` (entreprise, micro-entreprise,
# profession libérale, foyer avec PERSO), dans l'interface simplifiée et
# complète, plus les pages d'accès sans connexion et d'erreur, puis
# l'envoi de chaque formulaire relevé dans les pages (vide, valeurs
# fausses, bouton d'action tel quel), réponse, message flash et réponse
# HTMX contrôlés. Le contrôle
# est celui de l'interface (`PartiduoUi::Translations`, dans
# lib/partiduo-ui-bulma/spec/support/translations.cr) : ni marqueur de
# traduction absente, ni clé brute, ni interpolation non résolue, et toute
# route servie en `GET` atteinte, sauf exclusion motivée.
#
# Dossiers lus dans `PARTIDUO_DEMO_DOSSIERS`, sinon dans le dépôt voisin
# `../partiduo-demo/dossiers` (README, « Specs »).

private alias Demo = PartiduoDist::Demo

private DOSSIERS = ENV["PARTIDUO_DEMO_DOSSIERS"]?.presence || File.expand_path("../../partiduo-demo/dossiers", __DIR__)

# Routes servies en `GET` qui ne sont pas des pages à explorer.
private EXCLUSIONS = {
  "login_federated"          => "départ vers un fournisseur d'identité externe (redirection hors du site)",
  "login_federated_callback" => "retour d'un fournisseur d'identité : jeton externe exigé",
  "login_federated_acs"      => "réponse SAML, reçue en POST ; en GET, même handler que le retour OIDC",
  "invitation_connect"       => "départ vers connect (redirection hors du site)",
  "teledec_callback"         => "rappel de machine à machine de TELEDEC, sans page",
}

# Formulaires jamais envoyés : appel d'une plateforme externe que la spec
# ne simule pas (transport de test qui refuse tout autre hôte).
private UNSENT = {
  "superpdp:connect"    => "connexion à la plateforme SUPERPDP (api.superpdp.tech)",
  "einv:sync"           => "synchronisation avec la plateforme agréée (api.superpdp.tech)",
  "einv:settings_check" => "essai de connexion à la plateforme agréée (api.superpdp.tech)",
}

# Variables des modèles de relance, citées telles quelles dans l'aide des
# réglages de la Facturation.
private LITERALS = [PartiduoUi::InvoicingSettingsHandler::REMINDER_VARIABLES]

# Extensions que les dossiers de démonstration n'activent pas : ajoutées
# au dossier d'entreprise, pour que leurs écrans soient explorés.
private EXTRA = %w[sepa amortis reports import form esalink superpdp bankimport urssaf]

private def fresh! : Nil
  Marten::Spec.flush_databases
  Partiduo::Modules::State.reset_table_cache
  PartiduoUi::RateLimit.reset!
end

# Charge un dossier de démonstration, avec ses modules et extensions comme
# configuration de l'instance (`PARTIDUO_MODULES`, comme `partiduo-manage
# demo charger`) et les extensions `extra` ; ses utilisateurs ont le mot de
# passe des comptes de test. Rend l'adresse du premier (gérant, ADMIN).
private def load(code : String, extra : Array(String) = [] of String) : String
  fresh!
  dossier = Demo::Dossier.read(DOSSIERS, code)
  ENV["PARTIDUO_MODULES"] = ([dossier.active_codes] + extra).join(",")
  Demo::Simulators.install(dossier.siren, dossier.public_structures)
  passwords = dossier.identity.utilisateurs.to_h { |person| {person.email, PartiduoUi::Accounts::PASSWORD} }
  Demo::Loader.new(dossier, passwords).load
  extra.each { |extension| Partiduo::Api::Modules.activate(Partiduo::Api::Actor.system, extension.upcase) }
  dossier.identity.utilisateurs.first.email
end

# Formulaire public de FORM et son lien : page publique `/p/form/<jeton>`,
# remise au public, qu'aucune page du dossier n'appelle. Rend l'adresse.
private def public_form(email : String) : String
  system = Partiduo::Api::Actor.system
  user = Partiduo::Api::Auth.user_by_email(system, email) || raise "utilisateur #{email} absent"
  actor = Partiduo::Api::Actor.user(user.id, Partiduo::Api::Modules.permissions(system).map(&.name), level: 3)
  category = Partiduo::Api::Cards.category_by_code(system, "CUSTOMER") || raise "catégorie CUSTOMER absente"
  form = Forms::Api.create_form(actor, Forms::Api::FormInput.new(title: "Demande de devis", purpose: "Répondre à votre demande.",
    controller: "Menuiserie Lambert & Fils", retention_days: 30, category_id: category.id)).value!
  Forms::Api.add_field(actor, form.id, Forms::Api::FieldInput.new(key: "nom", label: "Nom", required: true, target: "name")).value!
  link = Forms::Api.create_link(actor, form.id, Forms::Api::LinkInput.new(expires_on: Partiduo::Config.today + 30.days,
    max_uses: 5, label: "Site")).value!
  "/p/form/#{link.token}"
end

# Comptable du dossier (rôle `accountant`, profil ADMIN) : interface
# complète des dossiers simplifiés.
private def accountant : PartiduoUi::Browser
  PartiduoUi::Accounts.create("expert@example.com", role: "accountant")
  PartiduoUi::Accounts.signed_in("expert@example.com")
end

describe "Traductions de toutes les pages de la distribution (fr, en, nl)" do
  it "rend chaque page du cœur et des extensions dans chaque langue, sans clé absente, brute ni interpolation non résolue" do
    pending!("dossiers de démonstration absents : #{DOSSIERS} (PARTIDUO_DEMO_DOSSIERS)") unless Dir.exists?(DOSSIERS)
    explorer = PartiduoUi::Translations::Explorer.new(EXCLUSIONS, literals: LITERALS, unsent: UNSENT) { true }

    explorer.visit_placeholders(PartiduoUi::Browser.new, "anonyme, instance vierge")

    gerante = load("atelier", EXTRA)
    explorer.visit_placeholders(PartiduoUi::Browser.new, "anonyme")
    browser = PartiduoUi::Accounts.signed_in(gerante)
    explorer.crawl(browser, "atelier")
    explorer.visit_placeholders(browser, "atelier, objets inconnus")
    anonymous = PartiduoUi::Browser.new
    explorer.crawl(anonymous, "anonyme, formulaire public", [public_form(gerante)])
    # Envoi de chaque formulaire relevé (vide, valeurs fausses, bouton
    # d'action tel quel) : erreurs, messages flash, réponses HTMX, refus.
    explorer.submit_forms(anonymous, "anonyme, formulaire public", explorer.forms.select(&.action.starts_with?("/p/")))
    explorer.submit_forms(browser, "atelier")

    {"micro", "liberal", "foyer"}.each do |code|
      email = load(code)
      member = PartiduoUi::Accounts.signed_in(email)
      explorer.crawl(member, "#{code}, simplifiée")
      explorer.crawl(accountant, "#{code}, complète") unless code == "foyer"
      explorer.submit_forms(member, code)
    end

    ENV.delete("PARTIDUO_MODULES")
    puts "\nTraductions : #{explorer.report}"
    (explorer.failures + explorer.unreached.map { |route| "route jamais atteinte : #{route}" }).should eq([] of String)
  end
end
