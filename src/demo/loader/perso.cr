# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # --- Foyer : finances personnelles (extension PERSO, ADR-011) -----------------

      # Membres, comptes du foyer (repris d'un compte du plan ou créés),
      # catégories propres et étiquettes fiscales, par `Perso::Api`.
      private def perso_settings(settings : Format::ParamPerso) : Nil
        members = {} of String => Int64
        settings.membres.each do |member|
          view = ok(Perso::Api.save_member(actor, Perso::Api::MemberInput.new(user_id(member.email) || 0_i64, member.prenom,
            member.role)), "membre #{member.prenom}")
          members[member.email] = view.id
        end
        settings.comptes.each do |account|
          holders = account.titulaires.map { |email| members[email]? || raise LoadError.new("titulaire #{email} : pas un membre du foyer") }
          input = Perso::Api::AccountInput.new(nature: account.nature, label: account.libelle, institution: account.etablissement,
            asset_kind: account.genre, rate: account.taux.try { |value| d(value) }, ceiling: account.plafond.try { |value| d(value) },
            opened_on: account.ouverture.try { |text| dates.date(text) }, holder_ids: holders, account_number: account.compte,
            opening_balance: account.solde_ouverture.try { |value| d(value) })
          ok(Perso::Api.create_account(actor, input), "compte du foyer #{account.libelle}")
        end
        settings.categories.each do |category|
          parent = category.parent.try { |label| perso_category(label).id } ||
                   category.parent_compte.try { |number| perso_category_by_account(number).id }
          ok(Perso::Api.create_category(actor, Perso::Api::CategoryInput.new(label: category.libelle, kind: category.sens,
            parent_id: parent, tax_tag: category.etiquette)), "catégorie #{category.libelle}")
        end
        settings.etiquettes.each do |tag|
          view = perso_category_by_account(tag.compte)
          ok(Perso::Api.update_category(actor, view.id, Perso::Api::CategoryInput.new(label: view.label, kind: view.kind,
            tax_tag: tag.etiquette, position: view.position, active: view.active)), "étiquette de #{view.label}")
        end
      end

      def perso_account(label : String) : Perso::Api::AccountView
        Perso::Api.accounts(actor).find(&.label.==(label)) || raise LoadError.new("compte du foyer « #{label} » absent")
      end

      def perso_category(label : String) : Perso::Api::CategoryView
        Perso::Api.categories(actor).find(&.label.==(label)) || raise LoadError.new("catégorie « #{label} » absente")
      end

      # Catégorie d'un compte du plan (`62`, `6101`) : le dossier de
      # démonstration s'y réfère par le numéro, que le foyer ne voit jamais.
      def perso_category_by_account(number : String) : Perso::Api::CategoryView
        Perso::Api.category_by_account(actor, number)
      rescue Api::NotFound
        raise LoadError.new("catégorie du compte #{number} absente")
      end

      def perso_member(email : String?) : Int64?
        email.try do |address|
          id = user_id(address)
          Perso::Api.members(actor).find(&.user_id.==(id)).try(&.id) || raise LoadError.new("membre #{address} absent")
        end
      end

      # Emprunt d'un compte de dette et première version de son tableau.
      def execute(operation : Format::PersoEmprunt, day : Time) : Nil
        insurance = operation.assurance
        input = Perso::Api::LoanInput.new(account_id: perso_account(operation.compte).id,
          payment_account_id: perso_account(operation.compte_payeur).id, principal: d(operation.capital),
          annual_rate: d(operation.taux), months: operation.echeances, first_due_on: dates.date(operation.premiere_echeance),
          interest_category_id: perso_category_by_account(operation.categorie_interets).id,
          insurance_category_id: operation.categorie_assurance.try { |number| perso_category_by_account(number).id },
          deferral_months: operation.differe, deferral_kind: operation.type_differe,
          insurance_mode: insurance.try(&.mode) || "none", insurance_value: insurance.try { |item| d(item.valeur) } || d("0"))
        ok(Perso::Api.create_loan(actor, input), "emprunt #{operation.compte}")
      end

      def execute(operation : Format::PersoRecurrente, day : Time) : Nil
        input = Perso::Api::RecurringInput.new(account_id: perso_account(operation.compte).id, payee: text(operation.beneficiaire, day),
          amount: d(operation.montant), first_on: operation.premiere.try { |value| dates.date(value) } || day,
          kind: operation.sens, category_id: operation.categorie.try { |number| perso_category_by_account(number).id },
          to_account_id: operation.vers.try { |label| perso_account(label).id }, estimated: operation.estime?,
          frequency: operation.frequence, interval_days: operation.intervalle,
          last_on: operation.derniere.try { |value| dates.date(value) }, business_days: operation.jour_ouvre?,
          member_id: perso_member(operation.membre))
        ok(Perso::Api.save_recurring(actor, input), "opération récurrente #{operation.beneficiaire}")
      end

      def execute(operation : Format::PersoValorisation, day : Time) : Nil
        lines = operation.lignes.map { |line| Perso::Api::ValuationLineInput.new(line.titre, d(line.quantite), d(line.cours)) }
        input = Perso::Api::ValuationInput.new(account_id: perso_account(operation.compte).id, valued_on: day,
          amount: operation.valeur.try { |value| d(value) }, lines: lines, note: text(operation.note, day))
        ok(Perso::Api.record_valuation(actor, input), "valorisation de #{operation.compte}")
      end

      # Budget d'une année : la prévision de la Comptabilité, puis un
      # montant par catégorie.
      def execute(operation : Format::PersoBudget, day : Time) : Nil
        year = dates.year(operation.annee)
        fiscal_year(year)
        ok(Perso::Api.create_budget(actor, year), "budget #{year}")
        operation.lignes.each do |line|
          input = Perso::Api::BudgetLineInput.new(perso_category_by_account(line.categorie).id, d(line.montant), line.periode)
          ok(Perso::Api.set_budget_line(actor, year, input), "budget de la catégorie #{line.categorie}")
        end
      end

      def execute(operation : Format::PersoDeplacements, day : Time) : Nil
        input = Perso::Api::TripInput.new(dates.year(operation.annee), operation.puissance, operation.kilometres,
          perso_member(operation.membre), text(operation.libelle, day))
        ok(Perso::Api.add_trip(actor, input), "déplacements #{operation.libelle}")
      end

      def execute(operation : Format::PersoOperation, day : Time) : Nil
        input = Perso::Api::OperationInput.new(account_id: perso_account(operation.compte).id, date: day,
          amount: d(operation.montant), kind: operation.sens,
          category_id: operation.categorie.try { |number| perso_category_by_account(number).id },
          to_account_id: operation.vers.try { |label| perso_account(label).id }, payee: text(operation.beneficiaire, day),
          member_id: perso_member(operation.membre), note: text(operation.note, day))
        ok(Perso::Api.record_operation(actor, input), "opération #{operation.beneficiaire}")
      end
    end
  end
end
