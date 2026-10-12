# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    # Vérification d'un dossier chargé : chaque contrôle d'`attendus.yml`
    # (grands totaux, nombres de documents, états) est relu par le contrat
    # et comparé à la valeur déclarée.
    class Verifier
      include Support

      record Outcome, label : String, expected : String, actual : String do
        def ok? : Bool
          expected == actual
        end
      end

      getter dossier : Dossier
      getter dates : Dates

      def initialize(@dossier : Dossier, today : Time = Partiduo::Config.today)
        @dates = Dates.new(today)
      end

      def run : Array(Outcome)
        dossier.expected.controles.map { |control| check(control) }
      end

      # Acteur du premier utilisateur du dossier, toutes permissions.
      private def actor : Api::Actor
        @actor ||= begin
          email = dossier.identity.utilisateurs.first.email
          user = Auth.user_by_email(system, email) || raise LoadError.new("utilisateur #{email} absent : dossier non chargé ?")
          Api::Actor.user(user.id, Api::Modules.permissions(system).map(&.name), level: 3)
        end
      end

      @actor : Api::Actor? = nil

      private def check(control : Format::Controle) : Outcome
        case control.type
        when "balance_equilibree"  then balanced(control)
        when "total_debit_minimum" then minimum_debit(control)
        when "solde_comptes"       then account_balance(control)
        when "declarations_tva"    then vat_returns(control)
        when "factures"            then invoices(control)
        when "releves"             then statements(control)
        when "mouvements_stock"    then stock_movements(control)
        when "teledeclarations"    then filings(control)
        when "rejets_reglement"    then rejections(control)
        when "micro_registres"     then micro_registers(control)
        when "urssaf_declarations" then urssaf(control)
        when "liberal_journal"     then liberal_journal(control)
        when "exercice_liberal"    then liberal_year(control)
        when "previsions"          then forecasts(control)
        else                            raise LoadError.new("attendus.yml : contrôle « #{control.type} » inconnu")
        end
      end

      private def year(control : Format::Controle) : Int32
        dates.year(control.exercice || raise LoadError.new("contrôle #{control.type} sans exercice"))
      end

      private def whole_year(year : Int32) : Acc::TrialBalanceQuery
        Acc::TrialBalanceQuery.new(date_from: Time.utc(year, 1, 1), date_to: Time.utc(year, 12, 31))
      end

      private def amount(text : String?) : String
        decimal(d(text || raise LoadError.new("montant attendu absent")))
      end

      private def balanced(control : Format::Controle) : Outcome
        year = year(control)
        balance = Acc.trial_balance(actor, whole_year(year))
        Outcome.new("balance équilibrée #{year} (écart débit − crédit)", "0.00", decimal(balance.delta))
      end

      private def minimum_debit(control : Format::Controle) : Outcome
        year = year(control)
        floor = d(control.montant || raise LoadError.new("total_debit_minimum sans montant"))
        total = Acc.trial_balance(actor, whole_year(year)).total.debit
        Outcome.new("total des débits #{year} ≥ #{decimal(floor)}", "oui", total >= floor ? "oui" : "non (#{decimal(total)})")
      end

      private def account_balance(control : Format::Controle) : Outcome
        year = year(control)
        prefix = control.prefixe || raise LoadError.new("solde_comptes sans prefixe")
        query = whole_year(year)
        control.journaux.try do |kind|
          ledger_kind = kind == "ventes" ? Acc::LedgerKind::Sale : (kind == "achats" ? Acc::LedgerKind::Purchase : nil)
          raise LoadError.new("solde_comptes : journaux « #{kind} » inconnus (ventes, achats)") unless ledger_kind
          query = query.copy_with(ledger_ids: Acc.ledgers(actor, ledger_kind).map(&.id))
        end
        rows = Acc.trial_balance(actor, query).rows.select(&.number.starts_with?(prefix))
        credit = control.sens == "credit"
        total = rows.sum(d(0)) { |row| credit ? row.credit - row.debit : row.debit - row.credit }
        label = "solde #{credit ? "créditeur" : "débiteur"} des comptes #{prefix}* #{year}"
        label += " (journaux de #{control.journaux})" if control.journaux
        Outcome.new(label, amount(control.montant), decimal(total))
      end

      private def vat_returns(control : Format::Controle) : Outcome
        year = year(control)
        form = control.formulaire || "fr_ca3"
        returns = Acc.vat_returns(actor, form, year)
        status = control.statut
        count = status ? returns.count(&.status.==(status)) : returns.size
        Outcome.new("déclarations #{form} #{year}#{status ? " (#{status})" : ""}", control.nombre.to_s, count.to_s)
      end

      private def invoices(control : Format::Controle) : Outcome
        year = year(control)
        list = Inv.documents(actor, Inv::DocumentQuery.new(kind: "invoice", from: Time.utc(year, 1, 1),
          to: Time.utc(year, 12, 31), limit: 1000))
        actual = list.size.to_s
        numbers = list.compact_map(&.number)
        actual += " (numéros en double)" unless numbers.uniq.size == list.size
        if control.comptabilisees
          missing = list.count { |invoice| Acc.entries(actor, Acc::EntryQuery.new(source: "invoice:#{invoice.id}")).empty? }
          actual += " (#{missing} sans écriture)" if missing > 0
        end
        Outcome.new("factures émises #{year}", control.nombre.to_s, actual)
      end

      private def statements(control : Format::Controle) : Outcome
        year = year(control)
        bank = Acc.ledgers(actor, Acc::LedgerKind::Financial).first? || raise LoadError.new("aucun journal financier")
        count = Acc.bank_statements(actor, bank.id).count(&.reference.ends_with?("/#{year}"))
        Outcome.new("relevés bancaires rapprochés #{year}", control.nombre.to_s, count.to_s)
      end

      private def stock_movements(control : Format::Controle) : Outcome
        count = Stk.movements(actor, Stk::MovementQuery.new).size
        minimum = control.minimum || 1
        Outcome.new("mouvements de stock ≥ #{minimum}", "oui", count >= minimum ? "oui" : "non (#{count})")
      end

      private def filings(control : Format::Controle) : Outcome
        list = Teledec::Api.filings(actor)
        status = control.statut
        kinds = list.select { |filing| status.nil? || filing.status == status }.map(&.kind).sort!
        expected = (control.natures || [] of String).sort
        Outcome.new("télédéclarations#{status ? " (#{status})" : ""}", expected.join(", "), kinds.join(", "))
      end

      private def rejections(control : Format::Controle) : Outcome
        list = Inv.payment_rejections(actor)
        actual = list.size.to_s
        control.frais.try do |fees|
          actual += " (frais #{list.map { |item| decimal(item.fees) }.join(", ")})" unless list.all?(&.fees.==(d(fees)))
        end
        Outcome.new("règlements rejetés", control.nombre.to_s, actual)
      end

      private def micro_registers(control : Format::Controle) : Outcome
        year = year(control)
        query = Api::Micro::RegisterQuery.new(from: Time.utc(year, 1, 1), to: Time.utc(year, 12, 31))
        receipts = Api::Micro.receipts_total(actor, query).amount
        purchases = Api::Micro.purchases_total(actor, query).amount
        Outcome.new("livre des recettes / registre des achats #{year}",
          "#{amount(control.recettes)} / #{amount(control.achats)}", "#{decimal(receipts)} / #{decimal(purchases)}")
      end

      private def urssaf(control : Format::Controle) : Outcome
        year = year(control)
        filed = Urssaf::Api.periods(actor, year).compact_map(&.filing).select(&.status.==("accepted"))
        actual = filed.size.to_s
        if control.payees
          unpaid = filed.count { |filing| filing.remaining > 0 }
          actual += " (#{unpaid} non payées)" if unpaid > 0
        end
        Outcome.new("déclarations URSSAF acceptées #{year}", control.nombre.to_s, actual)
      end

      private def liberal_journal(control : Format::Controle) : Outcome
        year = year(control)
        totals = Api::Liberal.journal_totals(actor, Api::Liberal::JournalQuery.new(from: Time.utc(year, 1, 1),
          to: Time.utc(year, 12, 31)))
        Outcome.new("livre-journal #{year} : recettes / dépenses",
          "#{amount(control.recettes)} / #{amount(control.depenses)}", "#{decimal(totals.receipts)} / #{decimal(totals.expenses)}")
      end

      private def liberal_year(control : Format::Controle) : Outcome
        year = year(control)
        Outcome.new("état de l'exercice #{year}", control.etat.to_s, Api::Liberal.year(actor, year).state)
      end

      private def forecasts(control : Format::Controle) : Outcome
        Outcome.new("prévisions budgétaires", control.nombre.to_s, Acc.forecasts(actor).size.to_s)
      end
    end
  end
end
