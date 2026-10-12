# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    # `partiduo-manage demo <action>` : charge un dossier de démonstration
    # décrit par des fichiers de données, ou vérifie ses grands totaux.
    #
    # ```
    # DATABASE_URL='postgres:///partiduo_demo_atelier?host=/tmp' \
    #   partiduo-manage demo charger --dossier=atelier --source=../partiduo-demo/dossiers --reset
    # DATABASE_URL='postgres:///partiduo_demo_atelier?host=/tmp' \
    #   partiduo-manage demo verifier --dossier=atelier --source=../partiduo-demo/dossiers
    # partiduo-manage demo modules --dossier=atelier --source=…       # PARTIDUO_MODULES du dossier
    # partiduo-manage demo utilisateurs --dossier=atelier --source=…  # une adresse par ligne
    # ```
    #
    # La base doit avoir « demo » dans son nom. Les mots de passe de test
    # viennent de `DEMO_PASSWORDS` (`adresse=mot de passe,…`) ; ceux qui
    # manquent sont générés et affichés. Services externes simulés.
    class Command < Marten::CLI::Manage::Command::Base
      command_name :demo
      help "Démonstration : charge un dossier fictif (charger), vérifie ses grands totaux (verifier), " \
           "affiche ses modules ou ses utilisateurs (modules, utilisateurs)."

      ACTIONS = %w[charger verifier modules utilisateurs]

      @action : String? = nil
      @code = ""
      @source = ""
      @reset = false
      @year : Int32? = nil

      def setup
        on_argument(:action, "action : #{ACTIONS.join(" ou ")}") { |value| @action = value }
        on_option_with_arg("dossier", "code", "code du dossier (répertoire de --source)") { |value| @code = value }
        on_option_with_arg("source", "répertoire", "répertoire des dossiers (partiduo-demo/dossiers)") { |value| @source = value }
        on_option("reset", "charger : vide d'abord le schéma de la base") { @reset = true }
        on_option_with_arg("annee", "AAAA", "verifier : année N du chargement (défaut : l'année en cours)") do |value|
          @year = value.to_i?
        end
      end

      def run
        action = @action
        unless action && ACTIONS.includes?(action)
          return print_error_and_exit("action attendue : #{ACTIONS.join(" ou ")}")
        end
        return print_error_and_exit("--dossier et --source sont obligatoires") if @code.empty? || @source.empty?
        dossier = Dossier.read(@source, @code)
        case action
        when "modules"      then return print(dossier.active_codes)
        when "utilisateurs" then return dossier.identity.utilisateurs.each { |user| print(user.email) }
        end
        unless Demo.demo_database?
          return print_error_and_exit("base refusée : « #{Demo.database_name} » ne contient pas « demo » (DATABASE_URL)")
        end
        ::Log.setup(::Log::Severity::Warn, Marten.settings.log_backend)
        # Modules et extensions de l'instance : ceux du dossier (comme
        # `PARTIDUO_MODULES` d'une instance réelle).
        ENV["PARTIDUO_MODULES"] = dossier.active_codes
        action == "charger" ? load(dossier) : verify(dossier)
      rescue ex : LoadError
        print_error_and_exit("#{@code} : #{ex.message}")
      end

      private def load(dossier : Dossier) : Nil
        Simulators.install(dossier.siren, dossier.public_structures)
        connection = Marten::DB::Connection.default
        if @reset
          print("== #{dossier.code} : base #{Demo.database_name} vidée")
          connection.open do |db|
            db.exec("DROP SCHEMA public CASCADE")
            db.exec("CREATE SCHEMA public")
          end
        end
        Marten::DB::Management::Migrations::Runner.new(connection).execute
        Partiduo::Modules::State.reset_table_cache
        if Api::Core.provisioned?(Api::Actor.system)
          return print_error_and_exit("#{dossier.code} : la base #{Demo.database_name} contient déjà un dossier (--reset)")
        end
        started = Time.instant
        print("== #{dossier.code} : chargement dans #{Demo.database_name}")
        loader = Loader.new(dossier, passwords_from_env)
        loader.load
        print("== #{dossier.code} : dossier chargé en #{(Time.instant - started).total_seconds.round(1)} s")
        loader.generated.each { |email, password| print("   identifiant de test : #{email} #{password}") }
      end

      private def verify(dossier : Dossier) : Nil
        today = @year.try { |year| Time.utc(year, 12, 31) } || Partiduo::Config.today
        outcomes = Verifier.new(dossier, today).run
        outcomes.each do |outcome|
          mark = outcome.ok? ? "ok   " : "ÉCART"
          detail = outcome.ok? ? outcome.actual : "attendu #{outcome.expected}, obtenu #{outcome.actual}"
          print("#{mark} #{outcome.label} : #{detail}")
        end
        failed = outcomes.count { |outcome| !outcome.ok? }
        if failed > 0
          print_error_and_exit("#{dossier.code} : #{failed} écart(s) sur #{outcomes.size} contrôle(s)")
        else
          print("== #{dossier.code} : #{outcomes.size} contrôles conformes")
        end
      end

      # `DEMO_PASSWORDS='adresse=mot de passe,adresse=mot de passe'`.
      private def passwords_from_env : Hash(String, String)
        ENV["DEMO_PASSWORDS"]?.to_s.split(',').each_with_object({} of String => String) do |pair, passwords|
          email, separator, password = pair.partition('=')
          passwords[email.strip] = password unless separator.empty?
        end
      end
    end
  end
end
