# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # Couleur de l'en-tête des copies de factures d'achat générées.
      INVOICE_COPY_COLOR = {120_u8, 72_u8, 40_u8}

      # --- Achats : factures reçues, plateforme agréée, justificatifs --------------

      # Facture fournisseur saisie (reçue hors plateforme), avec sa copie
      # numérisée si demandée, ventilée par la première clé analytique si
      # demandé, payée plus tard.
      def execute(operation : Format::Achat, day : Time) : Nil
        supplier = card(operation.fournisseur)
        number = text(operation.numero)
        lines = purchase_lines(operation.lignes)
        attachment_id = operation.copie? ? scanned_invoice(supplier, number, lines) : nil
        document = Acc::DocumentInput.new(ledger_id: ledger("achats").id, date: today, third_party: supplier.code,
          lines: lines, label: text(operation.libelle), due_date: operation.reglement.try { |payment| today + payment.delai.days },
          attachment_id: attachment_id)
        received = ok(Acc.post_received_invoice(actor, Acc::ReceivedInvoiceInput.new(document, number, today)),
          "facture #{number} de #{supplier.code}")
        entry = Acc.entry(actor, received.entry_id)
        remember(operation.ref, entry.id)
        distribute_purchase(entry) if operation.ventilation?
        operation.reglement.try { |payment| pay_supplier(entry, supplier, payment, text(operation.libelle)) }
      end

      # Facture d'un fournisseur reçue par la plateforme agréée simulée :
      # relevée par la synchronisation, pré-comptabilisée au journal
      # d'achats si `comptabiliser` le permet, puis payée.
      def execute(operation : Format::FacturePlateforme, day : Time) : Nil
        number = text(operation.numero)
        party = dossier.party(operation.fournisseur)
        lines = operation.lignes.map do |line|
          Ubl::Line.new(text(line.libelle), d(line.quantite.to_s), d(line.prix), line.unite)
        end
        content = Ubl.invoice(number, today, d(operation.taux), text(operation.note), party, buyer_siren: dossier.siren,
          buyer_name: identity.societe.nom, lines: lines)
        Simulators.platform.deliver(content, "#{number}.xml", "UBL")
        ok(Einvoicing::Api.synchronize(actor), "synchronisation avec la plateforme")
        reception = Einvoicing::Api.receptions(actor).find { |item| item.number == number } ||
                    raise LoadError.new("facture #{number} non relevée sur la plateforme")
        return unless applies?(operation.comptabiliser, day)
        received = ok(Einvoicing::Api.post(actor, reception.id), "pré-comptabilisation de #{number}")
        operation.reglement.try do |payment|
          pay_supplier(Acc.entry(actor, received.entry_id), card(operation.fournisseur), payment, text(operation.libelle))
        end
      end

      # Justificatif photographié (image générée) déposé dans la boîte
      # « Justificatifs à traiter » ; saisi en achat si `saisie` le
      # demande (et que sa condition est remplie), puis payé.
      def execute(operation : Format::Justificatif, day : Time) : Nil
        picture = operation.image
        raise LoadError.new("modèle d'image « #{picture.modele} » inconnu (ticket)") unless picture.modele == "ticket"
        total = d(operation.montant)
        image = Receipt.ticket(text(picture.enseigne), text(picture.adresse),
          picture.lignes.map { |line| {text(line.libelle), money(d(line.montant))} }, money(total), money(d(picture.tva)), today,
          picture.paiement, color(picture.couleur))
        details = Document::Api::DetailsInput.new(supplier_name: text(operation.nom_fournisseur),
          supplier_code: operation.fournisseur, amount: total, date: today, kind: operation.genre,
          reference: operation.reference.try { |value| text(value) } || "")
        receipt = ok(Document::Api.capture(actor, Document::Api::CaptureInput.new(text(operation.fichier), image,
          operation.source, details)), "justificatif photographié")
        entry = operation.saisie || return
        return unless applies?(entry.si, day)
        supplier = card(operation.fournisseur || raise LoadError.new("justificatif saisi sans fournisseur"))
        lines = purchase_lines(entry.lignes)
        prefill = Document::Api.purchase_prefill(actor, receipt.id, lines.first?.try(&.vat_rate) || "NOR")
        document = Acc::DocumentInput.new(ledger_id: ledger("achats").id, date: today, third_party: supplier.code,
          label: text(entry.libelle), lines: lines)
        number = prefill.number.presence || text(entry.numero)
        received = ok(Document::Api.post_purchase(actor, receipt.id, Acc::ReceivedInvoiceInput.new(document, number, today)),
          "saisie du justificatif")
        entry.reglement.try do |payment|
          pay_supplier(Acc.entry(actor, received.entry_id), supplier, payment, text(payment.libelle || entry.libelle))
        end
      end

      private def purchase_lines(lines : Array(Format::LigneAchat)) : Array(Acc::DocumentLineInput)
        lines.map do |line|
          if code = line.article
            quantity = line.quantite || raise LoadError.new("ligne d'achat #{code} sans quantité")
            price = line.prix || raise LoadError.new("ligne d'achat #{code} sans prix")
            Acc::DocumentLineInput.new(item: code, quantity: d(quantity.to_s), unit_price: d(price), vat_rate: line.taux)
          else
            amount = line.montant || raise LoadError.new("ligne d'achat sans article ni montant")
            Acc::DocumentLineInput.new(d(amount), account: line.compte, vat_rate: line.taux,
              vat_amount: line.tva.try { |value| d(value) }, label: text(line.libelle || ""))
          end
        end
      end

      private def color(values : Array(Int32)) : Receipt::Color
        raise LoadError.new("couleur : trois composantes attendues") unless values.size == 3
        {values[0].clamp(0, 255).to_u8, values[1].clamp(0, 255).to_u8, values[2].clamp(0, 255).to_u8}
      end

      # Ligne d'en-tête du client sur les copies de factures reçues.
      private def buyer_line : String
        company = identity.societe
        "#{company.nom} - #{company.code_postal} #{company.ville}".strip
      end

      # Copie numérisée de la facture du fournisseur (image générée), jointe
      # à l'écriture comme l'exige une facture reçue hors plateforme.
      private def scanned_invoice(supplier : Cards::CardView, number : String, lines : Array(Acc::DocumentLineInput)) : Int64
        rows = lines.map do |item|
          amount = item.unit_price.try { |price| price * (item.quantity || d(1)) } || item.amount
          label = item.item.try { |code| "#{item.quantity} X #{card(code).name}" } || item.label
          {label, amount, item.vat_rate == "NOR" ? (amount * BigDecimal.new("0.2")).round(2) : d(0)}
        end
        net = rows.sum(d(0), &.[1])
        vat = rows.sum(d(0), &.[2])
        party = dossier.reference.tiers.find(&.code.==(supplier.code))
        place = party.try(&.adresse).try { |item| "#{item.ligne1} #{item.code_postal} #{item.ville}" } || ""
        image = Receipt.invoice(supplier.name, place, number, today, rows.map { |row| {row[0], money(row[1])} }, money(net),
          money(vat), money(net + vat), INVOICE_COPY_COLOR, buyer_line)
        ok(Core.store_attachment(actor, Core::AttachmentInput.new("facture-#{number.downcase}.png", "image/png",
          IO::Memory.new(image))), "copie de la facture #{number}").id
      end

      private def pay_supplier(entry : Acc::EntryView, supplier : Cards::CardView, payment : Format::Reglement, label : String) : Nil
        agenda.at(today + payment.delai.days) do
          current = Acc.entry(actor, entry.id)
          ids, total = party_lines(current, supplier.id)
          next if ids.empty?
          ok(Acc.post_financial(actor, Acc::FinancialInput.new(ledger("banque").id, today, [
            Acc::PaymentLineInput.new(total, card: supplier.code, label: "Règlement #{supplier.name} — #{label}", match_line_ids: ids),
          ])), "règlement de #{supplier.code}")
        end
      end

      # Ventilation des lignes d'achats (60x) par la première clé de
      # répartition analytique.
      private def distribute_purchase(entry : Acc::EntryView) : Nil
        key = Ana.keys(actor).first? || return
        lines = entry.lines.select(&.account_number.starts_with?("60")).map do |entry_line|
          Ana::LineDistributionInput.new(entry_line.id, Ana.apply_key(actor, key.id, entry_line.amount))
        end
        ok(Ana.distribute_entry(actor, entry.id, lines), "ventilation de #{entry.receipt}") unless lines.empty?
      end
    end
  end
end
