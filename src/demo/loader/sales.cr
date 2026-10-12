# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # --- Ventes : factures, avoirs, devis, bons, règlements ------------------------

      def execute(operation : Format::Facture, day : Time) : Nil
        invoice = sell("invoice", operation.client, operation.lignes, operation.categorie, operation.objet,
          operation.reference_commande)
        remember(operation.ref, invoice.id)
        if operation.chorus_pro? && Choruspro::Api.invoices(actor).any?(&.id.==(invoice.id))
          ok(Choruspro::Api.transmit(actor, invoice.id), "dépôt sur Chorus Pro simulé")
        end
        operation.avoir.try { |credit| agenda.at(today + credit.delai.days) { credit_note(invoice, credit) } }
        operation.reglement.try { |payment| settle_later(invoice, payment) }
      end

      def execute(operation : Format::BonDeLivraison, day : Time) : Nil
        customer = card(operation.client)
        draft = ok(Inv.create_document(actor, Inv::DocumentInput.new(kind: "delivery_note", customer_card_id: customer.id,
          lines: sale_lines(operation.lignes), notes: text(operation.notes), operation_category: operation.categorie)),
          "bon de livraison pour #{customer.code}")
        issued = ok(Inv.issue(actor, draft.id, Inv::IssueInput.new(today)), "émission du bon de livraison")
        remember(operation.ref, issued.id)
      end

      # Bon de retour tiré d'un bon de livraison (entrée en stock à
      # l'émission), déduit de la facture récapitulative du mois.
      def execute(operation : Format::BonDeRetour, day : Time) : Nil
        draft = ok(Inv.transform(actor, recall(operation.bon), Inv::TransformInput.new("return_note")), "bon de retour")
        ok(Inv.update_document(actor, draft.id, Inv::DocumentInput.new(kind: "return_note",
          customer_card_id: draft.customer_card_id, lines: sale_lines(operation.lignes), return_reason: operation.motif,
          notes: text(operation.notes), operation_category: operation.categorie)), "motif du retour")
        issued = ok(Inv.issue(actor, draft.id, Inv::IssueInput.new(today)), "émission du bon de retour")
        remember(operation.ref, issued.id)
      end

      # Devis émis ; accepté (acompte, facture finale) ou refusé plus tard.
      def execute(operation : Format::Devis, day : Time) : Nil
        customer = card(operation.client)
        draft = ok(Inv.create_document(actor, Inv::DocumentInput.new(kind: "quote", customer_card_id: customer.id,
          lines: sale_lines(operation.lignes), notes: text(operation.objet), operation_category: operation.categorie)), "devis")
        quote = ok(Inv.issue(actor, draft.id, Inv::IssueInput.new(today)), "émission du devis")
        remember(operation.ref, quote.id)
        if accepted = operation.acceptation
          agenda.at(today + accepted.delai.days) { accept_quote(quote, accepted) }
        elsif refused = operation.refus
          agenda.at(today + refused.delai.days) { ok(Inv.decide_quote(actor, quote.id, "refused"), "devis refusé") }
        end
      end

      private def accept_quote(quote : Inv::DocumentView, accepted : Format::Acceptation) : Nil
        ok(Inv.decide_quote(actor, quote.id, "accepted"), "devis accepté")
        accepted.acompte.try do |percent|
          deposit = ok(Inv.transform(actor, quote.id, Inv::TransformInput.new("deposit_invoice", d(percent))), "facture d'acompte")
          deposit = issue(deposit)
          accepted.reglement_acompte.try { |payment| settle_later(deposit, payment) }
        end
        accepted.facture_finale.try do |final|
          agenda.at(today + final.delai.days) do
            invoice = issue(ok(Inv.transform(actor, quote.id, Inv::TransformInput.new("invoice")), "facture finale"))
            final.reglement.try { |payment| settle_later(invoice, payment) }
          end
        end
      end

      # Fin de mois planifiée (comme la tâche quotidienne de l'instance) :
      # factures récapitulatives proposées.
      def execute(operation : Format::FinDeMois, day : Time) : Nil
        Inv.month_end(actor, today)
      end

      # Factures récapitulatives proposées, émises et envoyées d'un clic.
      def execute(operation : Format::Recapitulatives, day : Time) : Nil
        Inv.issue_and_send_proposals(actor).each do |result|
          outcome = ok(result, "émission de la facture récapitulative")
          distribute_sale(outcome.document)
          operation.reglement.try { |payment| settle_later(outcome.document, payment) }
        end
      end

      # Virement retourné impayé : le règlement le plus récent d'un des
      # clients cités revient rejeté ; l'encaissement est contre-passé, les
      # frais refacturés par un brouillon de facture, relance proposée.
      def execute(operation : Format::RejetReglement, day : Time) : Nil
        customers = operation.clients.map { |code| card(code).id }
        paid = Inv.documents(actor, Inv::DocumentQuery.new(kind: "invoice", status: "paid", limit: 500))
          .select { |document| customers.includes?(document.customer_card_id) }
        candidates = paid.compact_map do |document|
          payment = Inv.payments(actor, document.id).reject(&.rejected?).max_by?(&.paid_on) || next
          payment if payment.paid_on < today
        end
        payment = candidates.max_by?(&.paid_on) || raise LoadError.new("aucun règlement à rejeter")
        ok(Inv.reject_payment(actor, payment.id, Inv::PaymentRejectionInput.new(rejected_on: today,
          reason: operation.motif, reason_text: text(operation.texte), fees: d(operation.frais), rebill_fees: operation.refacturer?,
          fees_vat_rate_id: operation.taux_frais.try { |code| rate(code) })), "rejet du règlement de #{payment.document_number}")
      end

      # Relances proposées au jour ; les `envoyer` premières sont envoyées.
      def execute(operation : Format::Relances, day : Time) : Nil
        proposed = Inv.propose_reminders(actor, today)
        proposed.first(operation.envoyer).each do |reminder|
          email = Inv.document(actor, reminder.document_id).customer.email
          next if email.empty?
          ok(Inv.send_reminder(actor, reminder.id, Inv::SendInput.new([email])), "relance de #{reminder.document_number}")
        end
      end

      private def sale_lines(lines : Array(Format::LigneVente)) : Array(Inv::LineInput)
        lines.map { |line| Inv::LineInput.new(item_card_id: card(line.article).id, quantity: d(line.quantite.to_s)) }
      end

      # Document créé puis émis au jour du dossier.
      private def sell(kind : String, customer_code : String, lines : Array(Format::LigneVente), category : String,
                       subject : String?, order_reference : String?) : Inv::DocumentView
        customer = card(customer_code)
        document = ok(Inv.create_document(actor, Inv::DocumentInput.new(kind: kind, customer_card_id: customer.id,
          lines: sale_lines(lines), notes: subject.try { |value| text(value) },
          order_reference: order_reference.try { |value| text(value) }, operation_category: category)),
          "#{kind} pour #{customer_code}")
        issue(document)
      end

      private def credit_note(invoice : Inv::DocumentView, credit : Format::Avoir) : Nil
        note = ok(Inv.create_document(actor, Inv::DocumentInput.new(kind: "credit_note", customer_card_id: invoice.customer_card_id,
          lines: sale_lines(credit.lignes), credited_document_id: invoice.id, notes: text(credit.motif),
          operation_category: credit.categorie)), "avoir sur #{invoice.number}")
        issue(note)
      end

      # Émission ; ventilation analytique et envoi par courriel si le
      # dossier les demande (`parametres.yml`).
      private def issue(document : Inv::DocumentView) : Inv::DocumentView
        issued = ok(Inv.issue(actor, document.id, Inv::IssueInput.new(today)), "émission de #{document.kind} #{document.id}")
        distribute_sale(issued)
        automatic = parameters.facturation.try(&.envoi_automatique?) || false
        if automatic && issued.issue_channel == "email" && !issued.customer.email.empty?
          ok(Inv.send_document(actor, issued.id, Inv::SendInput.new([issued.customer.email])), "envoi par courriel")
        end
        issued
      end

      # Écriture de vente générée par la Comptabilité pour un document émis.
      def sale_entry(document : Inv::DocumentView) : Acc::EntryView?
        return unless accounting?
        prefix = document.kind == "credit_note" ? "credit_note" : "invoice"
        Acc.entries(actor, Acc::EntryQuery.new(source: "#{prefix}:#{document.id}")).first? ||
          Acc.entries(actor, Acc::EntryQuery.new(source: "#{document.kind}:#{document.id}")).first?
      end

      def accounting? : Bool
        identity.modules.includes?("accounting")
      end

      # Ventilation analytique des lignes de produits (70x) d'une vente,
      # selon le poste de l'article (`poste` du référentiel).
      private def distribute_sale(document : Inv::DocumentView) : Nil
        return unless parameters.analytique.try(&.ventilation_ventes?)
        entry = sale_entry(document) || return
        items = dossier.reference.articles.select(&.categorie.==("vente"))
        lines = entry.lines.select(&.account_number.starts_with?("70")).compact_map do |entry_line|
          item = items.find { |row| row.nom == entry_line.label || entry_line.label.starts_with?(row.nom) }
          code = item.try(&.poste) || items.find(&.compte.==(entry_line.account_number)).try(&.poste) || next
          Ana::LineDistributionInput.new(entry_line.id, [Ana::DistributionRowInput.new(entry_line.amount, [post(code)])])
        end
        ok(Ana.distribute_entry(actor, entry.id, lines), "ventilation de #{entry.receipt}") unless lines.empty?
      end

      # Lignes du tiers (client ou fournisseur) d'une écriture, non lettrées,
      # et leur solde signé (débit positif).
      def party_lines(entry : Acc::EntryView, card_id : Int64) : {Array(Int64), BigDecimal}
        lines = entry.lines.select { |item| item.card_id == card_id && item.matching_id.nil? && item.account_number.starts_with?("4") }
        total = lines.sum(d(0)) { |item| item.side.debit? ? item.amount : -item.amount }
        {lines.map(&.id), total}
      end

      # Règlement d'un document de vente `delai` jours plus tard : en banque,
      # lettré avec la facture et ses avoirs (`banque`), ou saisi en
      # Facturation pour le total TTC (`encaissement`).
      def settle_later(document : Inv::DocumentView, payment : Format::Reglement) : Nil
        agenda.at(today + payment.delai.days) do
          case payment.mode
          when "banque"       then bank_receipt(document)
          when "encaissement" then record_payment(document, payment)
          else                     raise LoadError.new("règlement : mode « #{payment.mode} » inconnu (banque, encaissement)")
          end
        end
      end

      private def record_payment(document : Inv::DocumentView, payment : Format::Reglement) : Nil
        ok(Inv.record_payment(actor, Inv::PaymentInput.new(document.id, document.totals.total_gross, today,
          payment.moyen || "transfer")), "règlement de #{document.number}")
      end

      private def bank_receipt(document : Inv::DocumentView) : Nil
        current = Inv.document(actor, document.id)
        return if current.effective_status.in?("paid", "cancelled")
        entry = sale_entry(current) || return
        # Un avoir déjà lettré avec la facture (lettrage partiel) : le
        # lettrage est repris pour réunir facture, avoir et encaissement.
        entry.lines.select(&.card_id.==(current.customer_card_id)).each do |item|
          item.matching_id.try { |matching| ok(Acc.unmatch(actor, matching), "reprise du lettrage de #{current.number}") }
        end
        entry = Acc.entry(actor, entry.id)
        ids, total = party_lines(entry, current.customer_card_id)
        current.credit_notes.each do |link|
          credit = Inv.document(actor, link.id)
          (sale_entry(credit) || next).try do |credit_entry|
            more, amount = party_lines(credit_entry, current.customer_card_id)
            ids.concat(more)
            total += amount
          end
        end
        return if ids.empty? || total <= 0
        customer = Cards.card(system, current.customer_card_id)
        ok(Acc.post_financial(actor, Acc::FinancialInput.new(ledger("banque").id, today, [
          Acc::PaymentLineInput.new(total, card: customer.code, label: "Virement #{customer.name} #{current.number}",
            match_line_ids: ids),
        ])), "encaissement de #{current.number}")
      end
    end
  end
end
