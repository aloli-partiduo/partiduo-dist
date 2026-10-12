# SPDX-License-Identifier: AGPL-3.0-or-later

# Services externes simulés (doubles des specs de chaque extension, dans ce
# processus) : aucun appel réseau ne part d'une instance de démonstration.
# Ils ne sont branchés qu'en mode démonstration (commande `demo`, serveur
# lancé avec `PARTIDUO_DEMO=1`), jamais dans une instance réelle.
#
# * plateforme agréée XP Z12-013 simulée d'EINV, qui accuse d'elle-même
#   chaque flux déposé ;
# * TELEDEC simulé, qui accuse réception à la première relève ;
# * Chorus Pro simulé, avec les structures publiques du dossier ;
# * URSSAF simulée (micro-entrepreneur) ;
# * courriel : messages gardés en mémoire, jamais envoyés.
require "../../lib/partiduo-einvoicing/spec/support/platform"
require "../../lib/partiduo-teledec/spec/support/simulated_teledec"
require "../../lib/partiduo-choruspro/spec/support/simulated_chorus_pro"
require "../../lib/partiduo-urssaf/spec/support/simulated_urssaf"

module PartiduoDist
  module Demo
    module Simulators
      # Adresses de la plateforme simulée (hôte réservé `pa.test`, jamais
      # résolu : le transport simulé répond à la place du réseau).
      PLATFORM_VALUES = {
        "flow_url"        => "https://pa.test/afnor-flow",
        "directory_url"   => "https://pa.test/afnor-directory",
        "token_url"       => "https://pa.test/oauth2/token",
        "client_id"       => Einvoicing::SpecSupport::SimulatedPlatform::CLIENT_ID,
        "client_secret"   => Einvoicing::SpecSupport::SimulatedPlatform::CLIENT_SECRET,
        "organization_id" => "",
        "environment"     => "sandbox",
      }

      # SIREN par défaut de l'URSSAF simulée (dossier sans SIREN).
      DEFAULT_SIREN = "732829320"

      # Plateforme XP Z12-013 simulée qui contrôle d'elle-même chaque flux
      # déposé : accusé `Ok` (« Déposée ») à la lecture suivante des flux.
      class AutoAckPlatform < Einvoicing::SpecSupport::SimulatedPlatform
        def exec(request : Request) : Response
          if request.url.includes?("/flows/search")
            flows.each { |flow| acknowledge(flow, "Ok") if flow.direction == "Out" && flow.ack == "Pending" }
          end
          super
        end
      end

      # TELEDEC simulé qui accuse réception de chaque dépôt à la première
      # relève de son état, comme la DGFiP après quelques minutes.
      class AutoAckTeledec < Teledec::SimulatedTeledec
        def status(credentials : Teledec::Credentials, remote_id : String, reference : String = "") : Teledec::RemoteStatus
          deposit = deposits[remote_id]?
          acknowledge(remote_id) if deposit && deposit.report.nil?
          super
        end
      end

      class_getter platform = AutoAckPlatform.new
      class_getter mail = Partiduo::Invoicing::Mail::MemoryTransport.new
      class_getter? installed = false

      # Branche les doubles ; à appeler avant tout chargement et avant de
      # servir l'instance. `siren` : celui du dossier (URSSAF simulée) ;
      # `structures` : SIRET et nom des structures publiques (Chorus Pro).
      def self.install(siren : String, structures : Array({String, String})) : Nil
        @@platform.page_size = 50
        Einvoicing::Http.transport = @@platform
        Partiduo::Invoicing::Mail.transport = @@mail
        Teledec::Transports.current = AutoAckTeledec.new
        chorus = Choruspro::SimulatedChorusPro.new
        structures.each do |(siret, name)|
          chorus.structures[siret] = Choruspro::Structure.new(siret, name, false, false, [] of String)
        end
        Choruspro::Transports.current = chorus
        Urssaf::Transports.current = Urssaf::SimulatedUrssaf.new(siren.presence || DEFAULT_SIREN)
        @@installed = true
      end

      # Branche les doubles d'une instance déjà chargée (serveur) : SIREN du
      # dossier et structures publiques lus en base.
      def self.install_from_database : Nil
        system = Partiduo::Api::Actor.system
        siren = Partiduo::Api::Core.provisioned?(system) ? Partiduo::Api::Core.settings(system).siren.to_s.delete(' ') : ""
        install(siren, public_structures(system))
      end

      private def self.public_structures(system : Partiduo::Api::Actor) : Array({String, String})
        category = Partiduo::Api::Cards.category_by_code(system, "CUSTOMER") || return [] of {String, String}
        query = Partiduo::Api::Cards::CardQuery.new(category_id: category.id, limit: 1000)
        Partiduo::Api::Cards.cards(system, query).compact_map do |card|
          {card.siret, card.name} if card.customer_nature == "public" && !card.siret.empty?
        end
      rescue Partiduo::Api::NotFound
        [] of {String, String}
      end
    end
  end
end
