# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  # Démonstration : chargement de dossiers fictifs décrits par des fichiers
  # de données (dépôt `partiduo-demo`, `doc/format-dossiers.adoc`), par le
  # contrat `Partiduo::Api` et celui des extensions, jamais par SQL ;
  # vérification de leurs grands totaux ; services externes simulés.
  # Rien de ce module n'agit hors du mode démonstration : la commande
  # `demo` et le serveur lancé avec `PARTIDUO_DEMO=1` refusent toute base
  # dont le nom ne contient pas « demo ».
  module Demo
    alias Api = Partiduo::Api
    alias Acc = Partiduo::Api::Accounting
    alias Inv = Partiduo::Api::Invoicing
    alias Cards = Partiduo::Api::Cards
    alias Core = Partiduo::Api::Core
    alias Auth = Partiduo::Api::Auth
    alias Vat = Partiduo::Api::Vat
    alias Ana = Partiduo::Api::Analytic
    alias Stk = Partiduo::Api::Stock

    # Échec d'une étape du chargement ou d'une lecture des fichiers.
    class LoadError < Exception
    end

    # Nom de la base de la connexion par défaut.
    def self.database_name : String
      Marten.settings.databases.first.name.to_s
    end

    # Garde-fou : seules les bases dont le nom contient « demo » sont
    # chargées, vérifiées ou servies en mode démonstration.
    def self.demo_database? : Bool
      database_name.includes?("demo")
    end

    # Outils communs : montants, dates, résultats du contrat.
    module Support
      extend self

      def system : Api::Actor
        Api::Actor.system
      end

      def d(text : String | Int32) : BigDecimal
        BigDecimal.new(text.to_s)
      end

      # Valeur d'un résultat du contrat, ou `LoadError` qui cite l'étape et
      # les erreurs (clé et message traduit) : un chargement ne continue
      # jamais sur une étape refusée.
      def ok(result : Api::Result(T), what : String) : T forall T
        return result.value! if result.success?
        details = result.errors.map { |error| "#{error.field} : #{error.key} (#{error.message})" }.join(" ; ")
        raise LoadError.new("#{what} refusé : #{details}")
      end

      # Exécute le bloc à la date `day` (10 h, heure de Paris) : les
      # opérations prennent la date du jour du dossier à ce moment-là.
      def on(day : Time, &)
        Partiduo::Config.travel_to(Time.utc(day.year, day.month, day.day, 8, 0, 0)) { yield }
      end

      # Date du jour du dossier (horloge éventuellement déplacée).
      def today : Time
        Partiduo::Config.today
      end

      # Montant à deux décimales, point décimal (1234.50).
      def decimal(amount : BigDecimal) : String
        cents = (amount * 100).round.to_big_i
        sign = cents < 0 ? "-" : ""
        cents = cents.abs
        "#{sign}#{cents // 100}.#{(cents % 100).to_s.rjust(2, '0')}"
      end

      # Montant à la française pour les images et les messages (1 234,50).
      def money(amount : BigDecimal) : String
        whole, _, cents = decimal(amount).partition('.')
        negative = whole.starts_with?('-')
        digits = whole.lchop('-').reverse.scan(/\d{1,3}/).map(&.[0]).join(' ').reverse
        "#{negative ? "-" : ""}#{digits},#{cents}"
      end

      def say(text : String) : Nil
        STDOUT.puts "   #{text}"
        STDOUT.flush
      end
    end
  end
end
