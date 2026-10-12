# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    # Dates relatives des fichiers de données (`doc/format-dossiers.adoc`
    # de `partiduo-demo`), résolues au jour du chargement :
    #
    # * `N-1-03-06` : 6 mars de l'année précédant celle du chargement
    #   (`N`, `N-1`, `N+1`…) ; jour ramené à la fin du mois (`N-02-31`) ;
    # * `M-2-04` : 4 du mois situé deux mois avant celui du chargement ;
    # * `J`, `J-2`, `J+75` : jour du chargement, décalé en jours ;
    # * `2021-03-01` : date absolue ;
    # * suffixe `+17j` ou `-3j` : décalage en jours (`N-1-03-28+17j`).
    #
    # Périodes (mois) : `N-1-03` ou `2026-03`. Années : `N`, `N-1`, `2026`.
    struct Dates
      DATE   = /\A(?:(?<abs>\d{4})-(?<am>\d{2})-(?<ad>\d{2})|N(?<ny>[+-]\d+)?-(?<nm>\d{2})-(?<nd>\d{2})|M(?<mm>[+-]\d+)?-(?<md>\d{2}))(?:(?<shift>[+-]\d+)j)?\z/
      DAY    = /\AJ(?<shift>[+-]\d+)?\z/
      PERIOD = /\A(?:(?<abs>\d{4})|N(?<ny>[+-]\d+)?)-(?<month>\d{2})\z/
      YEAR   = /\A(?:(?<abs>\d{4})|N(?<ny>[+-]\d+)?)\z/

      # Jour du chargement (minuit UTC, forme des dates du cœur).
      getter today : Time

      def initialize(@today : Time)
      end

      def year : Int32
        @today.year
      end

      def date(text : String) : Time
        if match = DAY.match(text)
          return @today + (match["shift"]?.try(&.to_i) || 0).days
        end
        match = DATE.match(text) || raise LoadError.new("date illisible : « #{text} »")
        base = if abs = match["abs"]?
                 clamp(abs.to_i, match["am"].to_i, match["ad"].to_i)
               elsif match["nm"]?
                 clamp(year + (match["ny"]?.try(&.to_i) || 0), match["nm"].to_i, match["nd"].to_i)
               else
                 first = Time.utc(@today.year, @today.month, 1).shift(months: match["mm"]?.try(&.to_i) || 0)
                 clamp(first.year, first.month, match["md"].to_i)
               end
        base + (match["shift"]?.try(&.to_i) || 0).days
      end

      # Premier jour du mois d'une période.
      def period(text : String) : Time
        match = PERIOD.match(text) || raise LoadError.new("période illisible : « #{text} »")
        month = match["month"].to_i
        raise LoadError.new("période illisible : « #{text} »") unless 1 <= month <= 12
        Time.utc(year_of(match), month, 1)
      end

      def year(text : String) : Int32
        match = YEAR.match(text) || raise LoadError.new("année illisible : « #{text} »")
        year_of(match)
      end

      # Texte d'une donnée, jetons remplacés : `{aaaa}`, `{aa}`, `{mm}`,
      # `{jj}` (date de l'opération), `{N}`, `{N-1}`, `{N+1}` (années).
      def expand(text : String, day : Time? = nil) : String
        text.gsub(/\{(aaaa|aa|mm|jj|N(?:[+-]\d+)?)\}/) do |token|
          key = token[1..-2]
          if key.starts_with?('N')
            year(key).to_s
          else
            on = day || raise LoadError.new("jeton #{token} sans date dans « #{text} »")
            case key
            when "aaaa" then on.to_s("%Y")
            when "aa"   then on.to_s("%y")
            when "mm"   then on.to_s("%m")
            else             on.to_s("%d")
            end
          end
        end
      end

      private def year_of(match : Regex::MatchData) : Int32
        match["abs"]?.try(&.to_i) || year + (match["ny"]?.try(&.to_i) || 0)
      end

      private def clamp(year : Int32, month : Int32, day : Int32) : Time
        raise LoadError.new("mois invalide : #{month}") unless 1 <= month <= 12
        Time.utc(year, month, day.clamp(1, Time.days_in_month(year, month)))
      end
    end
  end
end
