# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # --- Comptabilité, banque, TVA, stock --------------------------------------------

      # Écriture saisie ligne à ligne (opérations diverses, à-nouveaux, paie).
      def execute(operation : Format::Ecriture, day : Time) : Nil
        lines = operation.lignes.map do |line|
          side, amount = if debit = line.debit
                           {Acc::Side::Debit, debit}
                         else
                           {Acc::Side::Credit, line.credit || raise LoadError.new("ligne #{line.compte} sans débit ni crédit")}
                         end
          Acc::EntryLineInput.new(line.compte, side, d(amount), card: line.tiers, label: text(line.libelle))
        end
        label = text(operation.libelle)
        entry = ok(Acc.post_entry(actor, Acc::EntryInput.new(ledger(operation.journal).id, today, lines, label,
          operation.piece.try { |value| text(value) })), label)
        remember(operation.ref, entry.id)
      end

      # Opérations d'un extrait bancaire (une écriture par ligne), montants
      # signés : positif pour une entrée en banque.
      def execute(operation : Format::Banque, day : Time) : Nil
        lines = operation.lignes.map do |line|
          Acc::PaymentLineInput.new(d(line.montant), card: line.tiers, account: line.compte, label: text(line.libelle))
        end
        ok(Acc.post_financial(actor, Acc::FinancialInput.new(ledger(operation.journal).id, today, lines)),
          text(operation.lignes.first?.try(&.libelle) || "extrait bancaire"))
      end

      # Déclaration de TVA de la période, close avec son écriture de
      # liquidation ; TVA due payée `delai` jours plus tard.
      def execute(operation : Format::DeclarationTva, day : Time) : Nil
        period = dates.period(operation.periode)
        label = period.to_s("%m/%Y")
        number = operation.periodicite == "month" ? period.month : (period.month - 1) // 3 + 1
        input = Acc::VatReturnInput.new(form: operation.formulaire, year: period.year, periodicity: operation.periodicite,
          number: number)
        created = ok(Acc.create_vat_return(actor, input), "déclaration de TVA de #{label}")
        id = created.id || raise LoadError.new("déclaration de TVA sans identifiant")
        closed = ok(Acc.close_vat_return(actor, id, Acc::VatSettlementInput.new(ledger_id: ledger(operation.journal).id, date: today)),
          "clôture de la déclaration de TVA de #{label}")
        payment = operation.paiement || return
        entry = closed.settlement_entry_id.try { |entry_id| Acc.entry(actor, entry_id) } || return
        due = entry.lines.select(&.account_number.==(payment.compte)).sum(d(0)) { |item| item.side.credit? ? item.amount : -item.amount }
        return unless due > 0
        wording = text(payment.libelle.gsub("{periode}", label))
        agenda.at(today + payment.delai.days) do
          ok(Acc.post_financial(actor, Acc::FinancialInput.new(ledger("banque").id, today, [
            Acc::PaymentLineInput.new(-due, account: payment.compte, label: wording),
          ])), wording)
        end
      end

      # Rapprochement du relevé du mois : toutes les opérations du journal
      # financier datées du mois (relevé « Relevé MM/AAAA »).
      def execute(operation : Format::Rapprochement, day : Time) : Nil
        first = dates.period(operation.mois)
        last = Time.utc(first.year, first.month, Time.days_in_month(first.year, first.month))
        bank = ledger(operation.journal).id
        view = Acc.reconciliation(actor, bank)
        ids = view.unreconciled.select { |item| first <= item.date <= last }.map(&.entry_id)
        return if ids.empty?
        ok(Acc.reconcile(actor, Acc::ReconcileInput.new(bank, "Relevé #{first.to_s("%m/%Y")}", ids)),
          "rapprochement de #{first.to_s("%m/%Y")}")
      end

      def execute(operation : Format::Inventaire, day : Time) : Nil
        lines = operation.lignes.map do |line|
          cost = line.cout || raise LoadError.new("inventaire : coût de #{line.article} absent")
          Stk::InventoryLineInput.new(card(line.article).id, d(line.quantite.to_s), d(cost))
        end
        ok(Stk.record_inventory(actor, Stk::InventoryInput.new(repository_id, today, lines, text(operation.libelle))),
          "inventaire")
      end

      # Mouvement de stock (fabrication : entrées au coût, sorties de
      # matières en quantités négatives).
      def execute(operation : Format::MouvementStock, day : Time) : Nil
        lines = operation.lignes.map do |line|
          quantity = d(line.quantite.to_s)
          if cost = line.cout
            Stk::ChangeLineInput.new(card(line.article).id, quantity, d(cost))
          else
            Stk::ChangeLineInput.new(card(line.article).id, quantity)
          end
        end
        ok(Stk.record_change(actor, Stk::ChangeInput.new(repository_id, today, lines, text(operation.libelle))),
          "mouvement de stock")
      end
    end
  end
end
