# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # --- Foyer : relevés importés, prévisions budgétaires ------------------------

      # Relevé du dossier importé par l'extension BANKIMPORT (années écrites
      # `{N-1}`, `{N}` dans le fichier, remplacées au chargement) : lignes
      # catégorisées par les règles, transférées en écritures, puis relevé
      # pointé par le rapprochement de la Comptabilité.
      def execute(operation : Format::ImportReleve, day : Time) : Nil
        content = dates.expand(String.new(dossier.read_bytes(operation.fichier)))
        bank = ledger(operation.journal).id
        input = Bankimport::Api::ImportInput.new(ledger_id: bank, filename: File.basename(operation.fichier),
          content: content.to_slice, format_id: csv_format(operation.format))
        imported = ok(Bankimport::Api.import_file(actor, input), "import de #{operation.fichier}")
        return unless operation.transferer?
        lines = Bankimport::Api.lines(actor, Bankimport::Api::LineQuery.new(import_id: imported.id, limit: 1000))
        ok(Bankimport::Api.apply_rules(actor, lines.map(&.id)), "catégorisation de #{operation.fichier}")
        report = ok(Bankimport::Api.transfer(actor, lines.map(&.id)), "transfert de #{operation.fichier}")
        unless report.failed.empty?
          raise LoadError.new("#{operation.fichier} : #{report.failed.size} ligne(s) non transférée(s), " \
                              "première : « #{report.failed.first.label} »")
        end
        operation.pointage.try do |statement|
          ok(Bankimport::Api.reconcile(actor, imported.id, Bankimport::Api::ReconcileInput.new(text(statement.reference),
            statement.solde_debut.try { |value| d(value) }, statement.solde_fin.try { |value| d(value) })),
            "pointage de #{operation.fichier}")
        end
      end

      # Prévision budgétaire sur une suite de périodes : catégories et
      # éléments (formule du réel, montant estimé de chaque période).
      def execute(operation : Format::Prevision, day : Time) : Nil
        first = period_id(dates.period(operation.debut))
        last = period_id(dates.period(operation.fin))
        forecast = ok(Acc.create_forecast(actor, Acc::ForecastInput.new(text(operation.nom), first, last)), "prévision")
        operation.categories.each_with_index do |group, rank|
          category = ok(Acc.create_forecast_category(actor, forecast.id, Acc::ForecastCategoryInput.new(text(group.libelle),
            (rank + 1) * 10)), "catégorie #{group.libelle}")
          group.elements.each_with_index do |item, position|
            ok(Acc.create_forecast_item(actor, category.id, Acc::ForecastItemInput.new(label: text(item.libelle),
              formula: item.formule, amount: d(item.montant), position: (position + 1) * 10)), "élément #{item.libelle}")
          end
        end
      end

      # Période du socle qui commence le premier jour du mois donné.
      private def period_id(first : Time) : Int64
        year = fiscal_year(first.year)
        Core.periods(system, year.id).find { |period| period.starts_on == first }.try(&.id) ||
          raise LoadError.new("période de #{first.to_s("%m/%Y")} absente")
      end
    end
  end
end
