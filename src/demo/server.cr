# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    # Serveur d'un dossier de démonstration déjà chargé (`partiduo-server`
    # lancé avec `PARTIDUO_DEMO=1` par `scripts/demo` de `partiduo-demo`) :
    # services externes simulés, fichier écrit quand le serveur est prêt
    # (`PARTIDUO_DEMO_READY_FILE`), arrêt à la création du fichier
    # `PARTIDUO_DEMO_STOP_FILE`. La base doit avoir « demo » dans son nom.
    module Server
      def self.enabled? : Bool
        ENV["PARTIDUO_DEMO"]? == "1"
      end

      def self.start : Nil
        Marten.configure(&.log_level=(::Log::Severity::Warn))
        Marten.setup
        abort "Base refusée : « #{Demo.database_name} » ne contient pas « demo » (DATABASE_URL)." unless Demo.demo_database?
        Simulators.install_from_database
        Marten::Server.setup
        address = "http://#{Marten.settings.host}:#{Marten.settings.port}/"
        ENV["PARTIDUO_DEMO_READY_FILE"]?.presence.try { |path| File.write(path, "#{address}\n") }
        ENV["PARTIDUO_DEMO_STOP_FILE"]?.presence.try { |path| watch(path) }
        Process.on_terminate { Marten::Server.stop }
        Marten::Server.start
      end

      private def self.watch(path : String) : Nil
        spawn do
          until File.exists?(path)
            sleep 1.second
          end
          Marten::Server.stop
          exit 0
        end
      end
    end
  end
end
