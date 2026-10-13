# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # Paramètres des modules et des extensions (`parametres.yml`). Les
      # services externes sont toujours ceux des simulateurs : les
      # identifiants viennent de leurs constantes, jamais des fichiers.
      private def load_parameters : Nil
        parameters.micro.try { |micro| micro_settings(micro) }
        parameters.liberal.try { |liberal| liberal_settings(liberal) }
        parameters.comptabilite.try(&.journal_achats).try do |settings|
          purchase = ledger("achats")
          ok(Acc.update_ledger(system, purchase.id, Acc::LedgerInput.new(name: purchase.name, kind: purchase.kind,
            code: purchase.code, description: purchase.description, enabled: true, default_account: settings.compte_defaut,
            receipt_prefix: purchase.receipt_prefix, receipt_padding: purchase.receipt_padding)), "journal d'achats")
        end
        parameters.facturation.try { |invoicing| invoicing_settings(invoicing) }
        parameters.einv.try do |einv|
          simulated!(einv.plateforme, "einv")
          ok(Einvoicing::Api.configure(actor, Einvoicing::Api::ConnectionInput.new(einv.profil || "AFNOR",
            Simulators::PLATFORM_VALUES)), "raccordement à la plateforme agréée simulée")
        end
        parameters.choruspro.try do |chorus|
          simulated!(chorus.plateforme, "choruspro")
          ok(Choruspro::Api.save_credentials(actor, Choruspro::Api::CredentialsInput.new(Choruspro::SimulatedChorusPro::CLIENT_ID,
            Choruspro::SimulatedChorusPro::CLIENT_SECRET, Choruspro::SimulatedChorusPro::LOGIN,
            Choruspro::SimulatedChorusPro::PASSWORD)), "identifiants Chorus Pro simulés")
        end
        parameters.teledec.try do |teledec|
          simulated!(teledec.plateforme, "teledec")
          ok(Teledec::Api.update_settings(actor, Teledec::Api::SettingsInput.new(teledec.regime, teledec.tva)), "paramètres TELEDEC")
          ok(Teledec::Api.save_credentials(actor, Teledec::Api::CredentialsInput.new(Teledec::SimulatedTeledec::LOGIN,
            Teledec::SimulatedTeledec::API_KEY, "sandbox", teledec.courriel, teledec.siret)), "identifiants TELEDEC simulés")
        end
        parameters.urssaf.try do |urssaf|
          simulated!(urssaf.plateforme, "urssaf")
          ok(Urssaf::Api.save_credentials(actor, Urssaf::Api::CredentialsInput.new(Urssaf::SimulatedUrssaf::CLIENT_ID,
            Urssaf::SimulatedUrssaf::CLIENT_SECRET)), "identifiants URSSAF simulés")
        end
        parameters.bankimport.try { |bankimport| bankimport_settings(bankimport) }
        parameters.perso.try { |perso| perso_settings(perso) }
      end

      # Un service externe de démonstration est toujours simulé.
      private def simulated!(value : String, code : String) : Nil
        return if value == "simulee"
        raise LoadError.new("parametres.yml : #{code}.plateforme doit valoir « simulee » (démonstration)")
      end

      private def invoicing_settings(settings : Format::ParamFacturation) : Nil
        input = Inv.settings(system).to_input
        settings.tva_sur_debits.try { |value| input = input.copy_with(vat_on_debits: value) }
        settings.iban.try { |value| input = input.copy_with(iban: value) }
        settings.bic.try { |value| input = input.copy_with(bic: value) }
        settings.courriel_expediteur.try { |value| input = input.copy_with(sender_email: value) }
        settings.nom_expediteur.try { |value| input = input.copy_with(sender_name: value) }
        settings.taux_penalites.try { |value| input = input.copy_with(late_penalty_rate: d(value)) }
        settings.categorie_operation.try { |value| input = input.copy_with(default_operation_category: value) }
        settings.delai_paiement.try { |value| input = input.copy_with(payment_terms_days: value) }
        ok(Inv.update_settings(system, input), "paramètres de la Facturation")
      end

      private def micro_settings(settings : Format::ParamMicro) : Nil
        Api::Micro.load_defaults(system) if Api::Micro.natures(system).empty?
        ok(Api::Micro.update_settings(actor, Api::Micro::SettingsInput.new(periodicity: settings.periodicite,
          activity_started_on: dates.date(settings.debut_activite), default_nature_id: micro_nature(settings.nature_defaut))),
          "paramètres de la micro-entreprise")
      end

      private def liberal_settings(settings : Format::ParamLiberal) : Nil
        Api::Liberal.load_defaults(system) if Api::Liberal.natures(system).empty?
        ok(Api::Liberal.update_settings(actor, Api::Liberal::SettingsInput.new(profession: settings.profession,
          activity_started_on: dates.date(settings.debut_activite), default_nature_id: liberal_nature(settings.rubrique_defaut))),
          "paramètres de la profession libérale")
      end

      def micro_nature(code : String) : Int64
        (Api::Micro.natures(system).find(&.code.==(code)) || raise LoadError.new("nature micro #{code} absente")).id
      end

      # Nature d'achat d'une catégorie (`goods`, `other`…).
      def micro_purchase_nature(category : String) : Int64
        natures = Api::Micro.natures(system, "purchase")
        (natures.find(&.category.==(category)) || natures.first? || raise LoadError.new("nature d'achat absente")).id
      end

      def liberal_nature(heading : String) : Int64
        (Api::Liberal.natures(system).find { |item| item.heading == heading && item.enabled } ||
          raise LoadError.new("rubrique #{heading} absente")).id
      end

      private def bankimport_settings(settings : Format::ParamBankimport) : Nil
        settings.formats.each do |format|
          columns = format.colonnes
          ok(Bankimport::Api.create_format(actor, Bankimport::Api::FormatInput.new(name: format.nom,
            date_column: columns.date, label_column: columns.libelle, amount_column: columns.montant,
            debit_column: columns.debit, credit_column: columns.credit, extra_column: columns.information,
            reference_column: columns.reference, counterparty_column: columns.tiers, institution: format.etablissement,
            ledger_id: ledger(format.journal).id, separator: format.separateur, encoding: format.encodage,
            skip_lines: format.lignes_entete, date_format: format.format_date, decimal_separator: format.separateur_decimal,
            thousands_separator: format.separateur_milliers, negate: format.inverser?)), "format CSV #{format.nom}")
        end
        settings.regles.each do |rule|
          ok(Bankimport::Api.create_rule(actor, Bankimport::Api::RuleInput.new(label_contains: rule.libelle_contient,
            amount: rule.montant.try { |value| d(value) }, direction: rule.sens, card_code: rule.tiers, account: rule.compte,
            position: rule.position)), "règle « #{rule.libelle_contient} »")
        end
      end

      def csv_format(name : String?) : Int64?
        return unless name
        (Bankimport::Api.formats(actor).find(&.name.==(name)) || raise LoadError.new("format CSV « #{name} » absent")).id
      end
    end
  end
end
