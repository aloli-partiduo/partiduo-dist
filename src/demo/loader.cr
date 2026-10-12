# SPDX-License-Identifier: AGPL-3.0-or-later

require "random/secure"

module PartiduoDist
  module Demo
    # Chargement d'un dossier de démonstration dans une base vierge : société
    # et type de dossier (provisionnement), utilisateurs et leurs mots de
    # passe de test, référentiel, paramètres, puis opérations datées jouées
    # au jour le jour jusqu'au jour du chargement, et opérations de fin.
    # Tout passe par le contrat `Partiduo::Api` et celui des extensions.
    class Loader
      include Support

      getter dossier : Dossier
      getter dates : Dates
      getter agenda : Agenda
      # Mots de passe de test par adresse (fournis par `scripts/demo` ou
      # générés ici : jamais écrits dans les fichiers du dossier).
      getter passwords : Hash(String, String)
      # Mots de passe générés par ce chargement, à communiquer.
      getter generated = {} of String => String

      @actor : Api::Actor? = nil
      # Documents et écritures nommés par `ref` dans les opérations.
      @refs = {} of String => Int64
      @posts = {} of String => Int64
      @repository_id : Int64? = nil

      def initialize(@dossier : Dossier, @passwords : Hash(String, String), today : Time = Partiduo::Config.today)
        @dates = Dates.new(today)
        @agenda = Agenda.new(today)
      end

      def identity : Format::DossierFile
        dossier.identity
      end

      def parameters : Format::Parametres
        dossier.parameters
      end

      def real_today : Time
        dates.today
      end

      # Charge tout le dossier ; rend le nombre d'opérations datées jouées.
      def load : Int32
        provision
        say "Référentiel et paramètres"
        identity.exercices.each { |text| fiscal_year(dates.year(text)) }
        load_accounts
        load_parameters
        load_reference
        schedule(dossier.operations.operations)
        schedule(dossier.operations.recentes)
        say "Opérations datées jusqu'au #{real_today.to_s("%d/%m/%Y")}"
        count = agenda.run
        say "#{count} opérations datées exécutées"
        unless dossier.operations.fin.empty?
          say "Opérations de fin de chargement"
          on(real_today) do
            dossier.operations.fin.each { |operation| perform(operation, real_today) }
          end
        end
        count
      end

      # --- Société, utilisateurs ------------------------------------------------------

      private def provision : Nil
        company = identity.societe
        domain = Partiduo::Config.domain
        settings = Core::SettingsInput.new(company_name: company.nom, legal_form: company.forme_juridique,
          share_capital: company.capital.try { |value| d(value) }, rcs: company.rcs, siren: company.siren,
          vat_number: company.tva, street: company.rue, street_number: company.numero, postcode: company.code_postal,
          city: company.ville, country_code: company.pays, phone: company.telephone, email: company.courriel,
          tax_regime: company.regime, default_locale: company.langue, domain: dossier.host(domain))
        say "Société « #{company.nom} » (#{identity.type} : #{dossier.active_codes})"
        input = Core::ProvisionInput.new(settings: settings, modules: identity.modules, extensions: identity.extensions,
          kind: identity.type)
        ok(Core.provision(system, input), "provisionnement")
        identity.extensions.each { |code| ok(Api::Modules.activate(system, code.upcase), "activation de #{code}") }
        profiles = Auth.ensure_default_profiles(system)
        identity.utilisateurs.each do |person|
          profile = profiles.find(&.code.==(person.profil)) || raise LoadError.new("profil #{person.profil} inconnu")
          password = passwords[person.email]? || generate_password(person.email)
          created = ok(Auth.create_user(system, Auth::UserInput.new(email: person.email, first_name: person.prenom,
            last_name: person.nom, role: person.role, profile_id: profile.id, password: password)),
            "utilisateur #{person.email}")
          # Invitation à créer une clé d'accès déjà vue : la démonstration
          # ouvre directement le tableau de bord.
          Auth.dismiss_passkey_prompt(Api::Actor.user(created.user.id, [] of String, level: 1))
        end
      end

      # Mot de passe de test : majuscule, minuscule et chiffre garantis
      # (politique du cœur).
      private def generate_password(email : String) : String
        alphabet = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a
        word = ->(size : Int32) { Array.new(size) { alphabet[Random::Secure.rand(alphabet.size)] }.join }
        @generated[email] = "Demo-#{word.call(8)}-#{word.call(6)}7"
      end

      # Acteur du premier utilisateur (gérant) avec toutes les permissions
      # déclarées : les opérations lui sont attribuées.
      def actor : Api::Actor
        @actor ||= begin
          user = Auth.user_by_email(system, identity.utilisateurs.first.email) || raise LoadError.new("utilisateur absent")
          permissions = Api::Modules.permissions(system).map(&.name)
          Api::Actor.user(user.id, permissions, level: 3)
        end
      end

      def user_id(email : String?) : Int64?
        return actor.user_id if email.nil?
        (Auth.user_by_email(system, email) || raise LoadError.new("utilisateur #{email} absent")).id
      end

      def fiscal_year(year : Int32) : Core::FiscalYearView
        Core.fiscal_years(system).find(&.year.==(year)) ||
          ok(Core.create_fiscal_year(system, Core::FiscalYearInput.new(year: year, start_year: year)), "exercice #{year}")
      end

      # --- Opérations -----------------------------------------------------------------

      # Inscrit les opérations à l'agenda, à leur date, si leur condition
      # (`si`) est remplie.
      private def schedule(operations : Array(Format::Operation)) : Nil
        operations.each do |operation|
          text = operation.date || raise LoadError.new("opération #{operation.type} sans date")
          day = dates.date(text)
          next unless applies?(operation.si, day)
          agenda.at(day) { perform(operation, day) }
        end
      end

      def applies?(condition : Format::Condition?, day : Time) : Bool
        return true unless condition
        condition.depuis.try { |text| return false if day < dates.date(text) }
        condition.avant.try { |text| return false unless day < dates.date(text) }
        true
      end

      # Exécute une opération au jour `day` (horloge déjà placée).
      private def perform(operation : Format::Operation, day : Time) : Nil
        execute(operation, day)
      rescue ex : LoadError
        raise LoadError.new("#{operation.type} du #{day.to_s("%d/%m/%Y")} : #{ex.message}")
      end

      def text(value : String, day : Time? = today) : String
        dates.expand(value, day)
      end

      def remember(ref : String?, id : Int64) : Nil
        ref.try { |key| @refs[key] = id }
      end

      def recall(ref : String) : Int64
        @refs[ref]? || raise LoadError.new("référence « #{ref} » inconnue (opération pas encore jouée ?)")
      end

      # --- Référentiel ------------------------------------------------------------------

      def category(code : String) : Int64
        (Cards.category_by_code(system, code) || raise LoadError.new("catégorie #{code} absente")).id
      end

      def rate(code : String) : Int64
        (Vat.rate_by_code(system, code) || raise LoadError.new("taux de TVA #{code} absent")).id
      end

      def card(code : String) : Cards::CardView
        Cards.card_by_code(system, code) || raise LoadError.new("fiche #{code} absente")
      end

      def ledger(kind : String) : Acc::LedgerView
        ledger_kind = case kind
                      when "banque" then Acc::LedgerKind::Financial
                      when "divers" then Acc::LedgerKind::Misc
                      when "achats" then Acc::LedgerKind::Purchase
                      when "ventes" then Acc::LedgerKind::Sale
                      else               raise LoadError.new("journal inconnu : « #{kind} » (banque, divers, achats, ventes)")
                      end
        Acc.ledgers(system, ledger_kind).first? || raise LoadError.new("aucun journal #{kind}")
      end

      def repository_id : Int64
        @repository_id || raise LoadError.new("aucun dépôt de stock déclaré au référentiel")
      end

      def post(code : String) : Int64
        @posts[code]? || raise LoadError.new("poste analytique #{code} absent")
      end

      def address(value : Format::Adresse?) : Cards::AddressInput?
        value.try { |item| Cards::AddressInput.new(line1: item.ligne1, postcode: item.code_postal, city: item.ville, country_code: item.pays) }
      end

      # Plan comptable propre et taux de TVA, avant les paramètres qui s'y
      # réfèrent (compte par défaut du journal d'achats).
      private def load_accounts : Nil
        reference = dossier.reference
        reference.comptes.each do |item|
          Acc.account(system, item.numero)
        rescue Api::NotFound
          ok(Acc.create_account(system, Acc::AccountInput.new(number: item.numero, label: item.libelle, parent: item.parent)),
            "compte #{item.numero}")
        end
        reference.taux_tva.each do |item|
          ok(Vat.create_rate(system, Vat::RateInput.new(code: item.code, label: item.libelle, rate: d(item.taux),
            category: item.categorie, exemption_code: item.exoneration_code, exemption_reason: item.exoneration_motif)),
            "taux #{item.code}")
        end
      end

      # Tiers, articles, analytique et stock.
      private def load_reference : Nil
        reference = dossier.reference
        reference.tiers.each { |party| create_party(party) }
        reference.articles.each { |item| create_item(item) }
        reference.analytique.try { |analytic| load_analytic(analytic) }
        reference.stock.try { |stock| load_stock(stock) }
      end

      private def create_party(party : Format::Tiers) : Nil
        customer = party.customer?
        individual = !customer && party.personne
        person = party.personne
        input = Cards::CardInput.new(category_id: category(customer ? "CUSTOMER" : "SUPPLIER"),
          name: individual ? "" : party.nom.to_s, code: party.code, siren: party.siren, siret: party.siret,
          email: party.courriel, vat_number: party.tva, address: address(party.adresse),
          customer_nature: customer ? party.nature : nil, supplier_nature: customer ? nil : party.nature,
          last_name: person.try(&.nom), first_names: person.try(&.prenoms),
          birth_date: person.try(&.naissance).try { |text| dates.date(text) }, description: person.try(&.description))
        created = ok(Cards.create_card(system, input), "tiers #{party.code}")
        party.facturation.try do |billing|
          ok(Inv.update_customer_billing(actor, created.id, Inv::CustomerBillingInput.new(billing.rythme,
            billing.encours_max.try { |value| d(value) })), "facturation de #{party.code}")
        end
      end

      private def create_item(item : Format::Article) : Nil
        sale = item.categorie == "vente"
        input = Cards::CardInput.new(category_id: category(sale ? "SALE" : "PURCHASE"), name: item.nom, code: item.code,
          unit_code: item.unite, sale_price: item.prix_vente.try { |value| d(value) },
          purchase_price: item.prix_achat.try { |value| d(value) }, vat_rate_id: item.taux.try { |code| rate(code) })
        created = ok(Cards.create_card(system, input), "article #{item.code}")
        item.compte.try do |number|
          ok(Acc.assign_card_account(system, Acc::AssignCardAccountInput.new(created.id, number)), "compte de #{item.code}")
        end
        item.nature_micro.try do |code|
          ok(Api::Micro.set_item_nature(actor, created.id, micro_nature(code)), "nature de #{item.code}")
        end
      end

      private def load_analytic(analytic : Format::Analytique) : Nil
        analytic.plans.each do |plan|
          created = ok(Ana.create_plan(actor, Ana::PlanInput.new(plan.nom, plan.description)), "plan analytique #{plan.nom}")
          plan.postes.each do |item|
            @posts[item.code] = ok(Ana.create_post(actor, Ana::PostInput.new(created.id, item.code, item.description)),
              "poste #{item.code}").id
          end
        end
        analytic.cles.each do |key|
          rows = key.repartition.map { |row| Ana::KeyRowInput.new(d(row.pourcentage), row.postes.map { |code| post(code) }) }
          ok(Ana.create_key(actor, Ana::KeyInput.new(key.nom, rows, key.description, key.journaux.map { |kind| ledger(kind).id })),
            "clé de répartition #{key.nom}")
        end
      end

      private def load_stock(stock : Format::StockFile) : Nil
        stock.depots.each do |depot|
          created = ok(Stk.create_repository(actor, Stk::RepositoryInput.new(depot.nom, depot.adresse, depot.ville, depot.pays,
            depot.telephone)), "dépôt #{depot.nom}")
          if depot.defaut? || @repository_id.nil?
            @repository_id = created.id
            ok(Stk.update_settings(actor, Stk::SettingsInput.new(created.id)), "dépôt par défaut") if depot.defaut?
          end
        end
        dossier.reference.articles.select(&.stock?).each do |item|
          ok(Stk.track_item(actor, Stk::ItemInput.new(card(item.code).id)), "suivi en stock de #{item.code}")
        end
      end
    end
  end
end
