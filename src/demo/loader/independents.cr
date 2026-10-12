# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # --- Micro-entrepreneur : livre des recettes, registre des achats, URSSAF -----

      def execute(operation : Format::MicroRecette, day : Time) : Nil
        ok(Api::Micro.record_receipt(actor, Api::Micro::ReceiptInput.new(date: today, nature_id: micro_nature(operation.nature),
          amount: d(operation.montant), method: operation.moyen, party_name: text(operation.tiers),
          label: text(operation.libelle))), "recette #{text(operation.libelle)}")
      end

      def execute(operation : Format::MicroAchat, day : Time) : Nil
        amount = d(operation.montant)
        attachment_id = operation.copie.try { |copy| micro_copy(copy, amount) }
        ok(Api::Micro.record_purchase(actor, Api::Micro::PurchaseInput.new(date: today,
          nature_id: micro_purchase_nature(operation.nature), amount: amount, method: operation.moyen,
          card_id: operation.fournisseur.try { |code| card(code).id }, party_name: text(operation.tiers),
          label: text(operation.libelle), reference: operation.reference.try { |value| text(value) } || "",
          attachment_id: attachment_id)), "achat #{text(operation.libelle)}")
      end

      # Facture du fournisseur (copie numérisée, montant TTC), jointe à
      # l'achat.
      private def micro_copy(copy : Format::CopieMicro, amount : BigDecimal) : Int64
        net = (amount * 100 / (d(copy.taux) + 100)).round(2)
        image = Receipt.invoice(text(copy.enseigne), text(copy.adresse), text(copy.numero), today,
          [{text(copy.libelle), money(amount)}], money(net), money(amount - net), money(amount), color(copy.couleur),
          buyer_line)
        ok(Core.store_attachment(actor, Core::AttachmentInput.new("facture-#{text(copy.numero).downcase}.png", "image/png",
          IO::Memory.new(image))), "copie de facture").id
      end

      # Mandat de déclaration et mandat de prélèvement SEPA, signés au jour.
      def execute(operation : Format::UrssafMandat, day : Time) : Nil
        ok(Urssaf::Api.sign_mandate(actor, Urssaf::Api::MandateInput.new(today, true)), "mandat URSSAF")
        ok(Urssaf::Api.notify_mandate(actor), "notification du mandat")
        ok(Urssaf::Api.register_sepa_mandate(actor, Urssaf::Api::SepaMandateInput.new(operation.iban, operation.bic,
          text(operation.titulaire), today, true)), "mandat de prélèvement SEPA")
      end

      # Déclaration de la période à l'URSSAF simulée, puis télépaiement.
      def execute(operation : Format::UrssafDeclaration, day : Time) : Nil
        starts_on = dates.period(operation.periode)
        ok(Urssaf::Api.declare(actor, starts_on), "déclaration URSSAF du #{starts_on.to_s("%m/%Y")}")
        ok(Urssaf::Api.pay(actor, starts_on), "télépaiement URSSAF du #{starts_on.to_s("%m/%Y")}") if operation.paiement?
      end

      # --- Profession libérale : livre-journal, immobilisations, clôture ------------

      def execute(operation : Format::LiberalRecette, day : Time) : Nil
        ok(Api::Liberal.record_receipt(actor, Api::Liberal::LineInput.new(date: today, nature_id: liberal_nature("receipts"),
          amount: d(operation.montant), method: operation.moyen, party_name: text(operation.tiers),
          label: text(operation.libelle))), "recette #{text(operation.libelle)}")
      end

      def execute(operation : Format::LiberalDepense, day : Time) : Nil
        ok(Api::Liberal.record_expense(actor, Api::Liberal::LineInput.new(date: today, nature_id: liberal_nature(operation.rubrique),
          amount: d(operation.montant), method: operation.moyen, party_name: text(operation.tiers), label: text(operation.libelle),
          nondeductible_amount: d(operation.part_privee))), "dépense #{text(operation.libelle)}")
      end

      def execute(operation : Format::LiberalImmobilisation, day : Time) : Nil
        ok(Api::Liberal.record_asset(actor, Api::Liberal::AssetInput.new(label: text(operation.libelle),
          category: operation.categorie, acquired_on: today, amount: d(operation.montant), duration_years: operation.duree,
          method: operation.moyen, party_name: text(operation.tiers))), "immobilisation #{text(operation.libelle)}")
      end

      # Clôture de l'exercice (la 2035 se transmet sur un exercice clôturé).
      def execute(operation : Format::LiberalCloture, day : Time) : Nil
        year = dates.year(operation.exercice)
        ok(Api::Liberal.close_year(actor, year), "clôture de l'exercice #{year}")
      end
    end
  end
end
