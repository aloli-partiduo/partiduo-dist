# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    # Agenda d'un chargement : chaque opération est datée ; elles s'exécutent
    # dans l'ordre chronologique (puis dans l'ordre de leur déclaration),
    # l'horloge du dossier placée à leur jour, et peuvent en programmer
    # d'autres (le règlement d'une facture à son échéance). Une opération
    # postérieure au jour du chargement n'a pas encore eu lieu : elle n'est
    # pas exécutée.
    class Agenda
      include Support

      record Event, day : Time, sequence : Int32, action : Proc(Nil)

      getter last_day : Time
      @events = [] of Event
      @sequence = 0

      def initialize(@last_day : Time)
      end

      def at(day : Time, &action : -> Nil) : Nil
        @sequence += 1
        @events << Event.new(day, @sequence, action)
      end

      def run : Int32
        count = 0
        until @events.empty?
          index = (0...@events.size).min_by { |position| {@events[position].day, @events[position].sequence} }
          event = @events.delete_at(index)
          next if event.day > @last_day
          on(event.day) { event.action.call }
          count += 1
        end
        count
      end
    end
  end
end
