# SPDX-License-Identifier: AGPL-3.0-or-later

require "option_parser"
require "./home"
require "./tools"
require "./backup"

module PartiduoDist
  module Local
    VERSION = {{
                (read_file("#{__DIR__}/../../shard.yml")
                  .lines
                  .find(&.starts_with?("version:")) || "version: 0.0.0")
                  .gsub(/^version:\s*/, "")
                  .chomp
              }}

    # Commande `partiduo` : dossiers locaux, sans serveur.
    module CLI
      USAGE = <<-TEXT
        Usage : partiduo dossier <action> [options]
                partiduo cle ajouter LIGNE|-   |   partiduo cle liste

        Dossiers sur ce poste, sans serveur : base dans le PostgreSQL du poste,
        servis à vous seul en http://<dossier>.partiduo.localhost:<port>/.

          creer NOM --name TEXTE --admin-email ADRESSE [options]
                                 crée le dossier et affiche le lien du premier accès
          ouvrir NOM             démarre son serveur et l'ouvre dans le navigateur
          fermer NOM             arrête son serveur
          liste                  liste les dossiers
          supprimer NOM --confirmer NOM
                                 supprime le dossier : base, pièces jointes, réglages
          sauvegarder NOM [--vers RÉP]
                                 sauvegarde chiffrée et signée, au format des serveurs
          restaurer NOM --cle FICHIER [--depuis RÉP] [--sauvegarde NOM-DE-SAUVEGARDE]
                        [--source DOSSIER] [--signataires FICHIER] [--remplacer]
                                 restaure la dernière sauvegarde (ou celle nommée) ;
                                 dossier existant : --remplacer, sauvegarde de sûreté d'abord

        Options de creer :
          --regime fr|be          régime fiscal (défaut : fr)
          --kind company|household
                                  entreprise (défaut) ou foyer
          --modules LISTE         modules (défaut : accounting,invoicing ;
                                  foyer : accounting)
          --with LISTE            extensions (einvoicing, perso, sepa…)
          --locale CODE           langue du dossier : fr, en, nl, de, es, it, pt
                                  (défaut : fr)
          -- …                    options de provisionnement en plus (--siren…)

        Sauvegardes (D-LOC-006) : chiffrées pour vos clés publiques (partiduo cle
        ajouter), dans <PARTIDUO_HOME>/sauvegardes par défaut ; copiez ce répertoire
        sur une clé USB ou un NAS. Votre clé privée et sa phrase de passe restent
        hors de ce poste ; restaurer les demande (--cle).

        Répertoire : PARTIDUO_HOME, sinon $XDG_DATA_HOME/partiduo, sinon
        ~/.local/share/partiduo. PostgreSQL : PGHOST (socket, défaut /tmp),
        PARTIDUO_PG_BIN (ses outils hors du PATH).
        TEXT

      def self.run(args : Array(String), home : Home = Home.new) : Int32
        if args.empty? || {"-h", "--help", "aide"}.includes?(args.first)
          puts USAGE
          return 0
        end
        if {"-v", "--version", "version"}.includes?(args.first)
          puts "partiduo #{VERSION}"
          return 0
        end
        return cle(home, args[1..]) if args.first == "cle"
        unless args.first == "dossier" && args.size >= 2
          STDERR.puts USAGE
          return 64
        end
        action = args[1]
        rest = args[2..]
        case action
        when "creer"       then creer(home, rest)
        when "ouvrir"      then ouvrir(home, rest)
        when "fermer"      then fermer(home, rest)
        when "liste"       then liste(home)
        when "supprimer"   then supprimer(home, rest)
        when "sauvegarder" then sauvegarder(home, rest)
        when "restaurer"   then restaurer(home, rest)
        else
          STDERR.puts "partiduo : action inconnue : #{action}"
          STDERR.puts USAGE
          64
        end
      rescue ex : Error | OptionParser::Exception
        STDERR.puts "partiduo : #{ex.message}"
        1
      end

      # --- creer --------------------------------------------------------------

      def self.creer(home : Home, args : Array(String)) : Int32
        provision_extra = [] of String
        if index = args.index("--")
          provision_extra = args[(index + 1)..]
          args = args[0...index]
        end
        label = admin = ""
        regime = "fr"
        kind = "company"
        locale = "fr"
        modules = extensions = nil
        names = [] of String
        OptionParser.parse(args) do |parser|
          parser.on("--name TEXTE", "raison sociale ou nom du foyer") { |value| label = value }
          parser.on("--admin-email ADRESSE", "votre adresse : premier accès au dossier") { |value| admin = value }
          parser.on("--regime CODE", "fr ou be") { |value| regime = value }
          parser.on("--kind TYPE", "company ou household") { |value| kind = value }
          parser.on("--modules LISTE", "modules activés") { |value| modules = value }
          parser.on("--with LISTE", "extensions activées") { |value| extensions = value }
          parser.on("--locale CODE", "fr, en, nl, de, es, it ou pt") { |value| locale = value }
          parser.unknown_args { |rest| names = rest }
        end
        raise Error.new("un nom de dossier attendu (minuscules, chiffres, tirets)") unless names.size == 1
        name = names.first
        raise Error.new("nom de dossier refusé : #{name} (minuscules, chiffres, tirets)") unless Local.valid_name?(name)
        raise Error.new("--name obligatoire (raison sociale ou nom du foyer)") if label.strip.empty?
        raise Error.new("--admin-email obligatoire : c'est le premier accès au dossier") unless admin.matches?(/\A[^@\s]+@[^@\s]+\z/)
        raise Error.new("--kind : company ou household") unless {"company", "household"}.includes?(kind)
        dossier = home.dossier(name)
        raise Error.new("le dossier #{name} existe déjà (#{dossier.dir})") if dossier.exists? || Dir.exists?(dossier.dir)
        database = Local.database_for(name)
        raise Error.new("la base #{database} existe déjà dans PostgreSQL : choisissez un autre nom") if Postgres.exists?(database)

        chosen = modules
        modules_list = chosen ? chosen : (kind == "household" ? "accounting" : "accounting,invoicing")
        extensions_list = extensions
        active = [modules_list, extensions].compact.join(',').split(',').map(&.strip).reject(&.empty?).uniq!.join(',')
        port = home.free_port
        env = {
          "MARTEN_ENV"              => "local",
          "MARTEN_SECRET_KEY"       => Local.secret_key,
          "DATABASE_URL"            => Postgres.database_url(database),
          "PARTIDUO_DOMAIN"         => DOMAIN,
          "PARTIDUO_MODULES"        => active,
          "PARTIDUO_MEDIA_ROOT"     => dossier.media_dir,
          "PARTIDUO_MODELES_PDF"    => "auto",
          "PORT"                    => port.to_s,
          "PARTIDUO_LOCAL_NAME"     => label.strip.gsub('\n', ' '),
          "PARTIDUO_LOCAL_DATABASE" => database,
        }
        # Développement (programmes hors paquet) : fichiers statiques collectés
        # dans le répertoire de l'utilisateur.
        env["PARTIDUO_ASSETS_ROOT"] = File.join(home.root, "assets") unless Programs.installed_assets?

        puts "== Dossier #{name} : base #{database}, http://#{Local.host_for(name)}:#{port}/"
        Dir.mkdir_p(dossier.media_dir, 0o700)
        Postgres.createdb(database)
        begin
          Programs.run!("partiduo-manage", ["migrate"], env, echo: false)
          provision = ["provision", "--name", label.strip, "--regime", regime, "--kind", kind, "--modules", modules_list,
                       "--locale", locale, "--domain", Local.host_for(name), "--admin-email", admin] of String
          if list = extensions_list
            provision += ["--with", list]
          end
          output = Programs.run!("partiduo-manage", provision + provision_extra, env)
          collect_assets(env)
          dossier.save(env)
          link = Local.invitation_url(output, name, port)
          puts
          puts "Dossier créé. Ouvrez-le, puis suivez le lien du premier accès :"
          puts "  partiduo dossier ouvrir #{name}"
          puts "  #{link || "(lien d'invitation introuvable dans la sortie ci-dessus)"}"
        rescue ex
          STDERR.puts "partiduo : création interrompue, base et répertoire retirés"
          Postgres.dropdb(database) rescue nil
          FileUtils.rm_rf(dossier.dir)
          raise ex
        end
        0
      end

      private def self.collect_assets(env : Hash(String, String)) : Nil
        root = env["PARTIDUO_ASSETS_ROOT"]? || return
        return if Dir.exists?(root) && !Dir.empty?(root)
        puts "== Fichiers statiques collectés dans #{root}"
        Programs.run!("partiduo-manage", ["collectassets", "--no-input"], env, echo: false)
      end

      # --- ouvrir, fermer -----------------------------------------------------

      def self.ouvrir(home : Home, args : Array(String)) : Int32
        browser = true
        names = [] of String
        OptionParser.parse(args) do |parser|
          parser.on("--sans-navigateur", "n'ouvre pas le navigateur") { browser = false }
          parser.unknown_args { |rest| names = rest }
        end
        dossier = existing(home, names)
        unless dossier.open?
          start(dossier)
        end
        puts "Dossier #{dossier.name} ouvert : #{dossier.url}"
        launch_browser(dossier.url) if browser
        0
      end

      # Serveur détaché du terminal (`nohup`), journal dans le dossier ; prêt
      # quand son port répond.
      private def self.start(dossier : Dossier) : Nil
        port = dossier.port
        raise Error.new("port #{port} déjà occupé sur ce poste : fermez ce qui l'utilise") unless Local.port_free?(port)
        log = File.open(dossier.log_path, "a", perm: 0o600)
        process = Process.new("/usr/bin/nohup", [Programs.path("partiduo-server")], env: dossier.env,
          chdir: dossier.dir, input: Process::Redirect::Close, output: log, error: log)
        log.close
        File.write(dossier.pid_path, "#{process.pid}\n", perm: 0o600)
        60.times do
          return if Local.listening?(port)
          if process.terminated?
            raise Error.new("le serveur de #{dossier.name} s'est arrêté au démarrage ; fin du journal :\n#{tail(dossier.log_path)}")
          end
          sleep 1.second
        end
        raise Error.new("le serveur de #{dossier.name} ne répond pas après 60 s ; journal : #{dossier.log_path}")
      end

      private def self.tail(path : String, count : Int32 = 15) : String
        File.read_lines(path).last(count).join('\n')
      rescue File::Error
        ""
      end

      private def self.launch_browser(url : String) : Nil
        opener = {% if flag?(:darwin) %} "open" {% else %} "xdg-open" {% end %}
        return unless Process.find_executable(opener)
        Process.run(opener, [url], output: Process::Redirect::Close, error: Process::Redirect::Close)
      rescue File::NotFoundError | IO::Error
      end

      def self.fermer(home : Home, args : Array(String)) : Int32
        dossier = existing(home, args)
        stop(dossier)
        puts "Dossier #{dossier.name} fermé."
        0
      end

      private def self.stop(dossier : Dossier) : Nil
        if pid = dossier.pid
          begin
            Process.signal(Signal::TERM, pid)
            20.times do
              break unless Process.exists?(pid)
              sleep 0.5.seconds
            end
            Process.signal(Signal::KILL, pid) if Process.exists?(pid)
          rescue ex : RuntimeError
            raise Error.new("serveur de #{dossier.name} (processus #{pid}) non arrêté : #{ex.message}")
          end
        end
        File.delete(dossier.pid_path) if File.exists?(dossier.pid_path)
      end

      # --- liste, supprimer ---------------------------------------------------

      def self.liste(home : Home) : Int32
        dossiers = home.dossiers
        if dossiers.empty?
          puts "Aucun dossier (#{home.dossiers_dir})."
          return 0
        end
        dossiers.each do |dossier|
          state = dossier.open? ? "ouvert" : "fermé "
          puts "#{dossier.name.ljust(20)} #{state}  #{dossier.url.ljust(44)} #{dossier.label}"
        end
        0
      end

      def self.supprimer(home : Home, args : Array(String)) : Int32
        confirm = ""
        names = [] of String
        OptionParser.parse(args) do |parser|
          parser.on("--confirmer NOM", "répéter le nom du dossier") { |value| confirm = value }
          parser.unknown_args { |rest| names = rest }
        end
        dossier = existing(home, names)
        unless confirm == dossier.name
          raise Error.new("suppression DÉFINITIVE de #{dossier.name} (base, pièces jointes, réglages) : " \
                          "répétez son nom, --confirmer #{dossier.name}")
        end
        stop(dossier)
        Postgres.dropdb(dossier.database)
        FileUtils.rm_rf(dossier.dir)
        puts "Dossier #{dossier.name} supprimé."
        0
      end

      # --- cle, sauvegarder, restaurer (D-LOC-006) ----------------------------

      def self.cle(home : Home, args : Array(String)) : Int32
        backups = Backups.new(home)
        case args.first?
        when "ajouter"
          raise Error.new("partiduo cle ajouter age1pq1… (ou - pour la lire sur l'entrée standard)") unless args.size == 2
          line = args[1] == "-" ? STDIN.gets_to_end : args[1]
          fingerprint = backups.add_recipient(line)
          puts "Clé ajoutée (#{fingerprint[0, 16]}…) : les sauvegardes suivantes sont chiffrées pour elle."
        when "liste"
          backups.recipients.each { |recipient| puts "#{Crypto.recipient_fingerprint(recipient)[0, 16]}…  #{recipient[0, 30]}…" }
          puts "Clé de signature de ce poste (#{Backups.station}) : #{backups.signing_public_line}"
        else
          raise Error.new("partiduo cle ajouter LIGNE|-  ou  partiduo cle liste")
        end
        0
      end

      def self.sauvegarder(home : Home, args : Array(String)) : Int32
        store = ""
        names = [] of String
        OptionParser.parse(args) do |parser|
          parser.on("--vers RÉP", "stockage des sauvegardes") { |value| store = value }
          parser.unknown_args { |rest| names = rest }
        end
        dossier = existing(home, names)
        backups = Backups.new(home)
        result = backups.take(dossier, store.presence || backups.default_store)
        puts "Sauvegarde de #{dossier.name} : #{File.join(result.store, result.locator.server, dossier.name)}/#{result.locator.stem}.*"
        puts "Chiffrée pour vos clés (capsule #{result.locator.stem}.key.age) et signée par ce poste. " \
             "Copiez le répertoire #{result.store} ailleurs (clé USB, NAS)."
        0
      end

      def self.restaurer(home : Home, args : Array(String)) : Int32
        key = store = stem = source = signers_file = ""
        replace = false
        names = [] of String
        OptionParser.parse(args) do |parser|
          parser.on("--cle FICHIER", "votre clé privée (fichier age, chiffré par phrase de passe)") { |value| key = value }
          parser.on("--depuis RÉP", "stockage des sauvegardes") { |value| store = value }
          parser.on("--sauvegarde NOM", "sauvegarde précise (backup-AAAAMMJJTHHMMSSZ)") { |value| stem = value }
          parser.on("--source DOSSIER", "dossier sauvegardé, s'il diffère (ex. une sauvegarde de serveur)") { |value| source = value }
          parser.on("--signataires FICHIER", "lignes allowed_signers des serveurs dont vient la sauvegarde") { |value| signers_file = value }
          parser.on("--remplacer", "remplace un dossier existant") { replace = true }
          parser.unknown_args { |rest| names = rest }
        end
        raise Error.new("un nom de dossier attendu") unless names.size == 1
        name = names.first
        raise Error.new("nom de dossier refusé : #{name}") unless Local.valid_name?(name)
        raise Error.new("--cle FICHIER obligatoire : votre clé privée ouvre la capsule de la sauvegarde") if key.empty?
        backups = Backups.new(home)
        store_dir = store.presence || backups.default_store
        signers = signers_file.empty? ? [] of String : File.read_lines(signers_file).reject { |line| line.strip.empty? || line.starts_with?('#') }
        locator = backups.find(store_dir, source.presence || name, stem.presence)
        verified = backups.verify(store_dir, locator, signers)
        puts "== Sauvegarde #{locator} (#{verified.manifest.taken_at.to_s("%Y-%m-%d %H:%M UTC")}), signature vérifiée"
        dossier = home.dossier(name)
        if dossier.exists?
          raise Error.new("le dossier #{name} existe : --remplacer pour le remplacer par la sauvegarde") unless replace
          raise Error.new("le dossier #{name} est ouvert : fermez-le d'abord (partiduo dossier fermer #{name})") if dossier.open?
          identity = backups.open_capsule(verified, key)
          safety = backups.take(dossier, store_dir, "pre-restore")
          puts "== Sauvegarde de sûreté : #{safety.locator.stem}"
          backups.restore(verified, identity, dossier)
          Programs.run!("partiduo-manage", ["migrate"], dossier.env, echo: false)
        else
          identity = backups.open_capsule(verified, key)
          restore_new(home, backups, dossier, verified, identity)
        end
        puts "Dossier #{name} restauré : partiduo dossier ouvrir #{name}"
        0
      end

      # Dossier neuf depuis une sauvegarde : réglages tirés comme à la
      # création (port, clé secrète), base et pièces jointes de la
      # sauvegarde, modules lus dans la base restaurée.
      private def self.restore_new(home : Home, backups : Backups, dossier : Dossier, verified : Backups::Verified,
                                   identity : String) : Nil
        database = Local.database_for(dossier.name)
        raise Error.new("la base #{database} existe déjà dans PostgreSQL") if Postgres.exists?(database)
        port = home.free_port
        env = {
          "MARTEN_ENV"              => "local",
          "MARTEN_SECRET_KEY"       => Local.secret_key,
          "DATABASE_URL"            => Postgres.database_url(database),
          "PARTIDUO_DOMAIN"         => DOMAIN,
          "PARTIDUO_MODULES"        => "accounting,invoicing",
          "PARTIDUO_MEDIA_ROOT"     => dossier.media_dir,
          "PARTIDUO_MODELES_PDF"    => "auto",
          "PORT"                    => port.to_s,
          "PARTIDUO_LOCAL_NAME"     => "#{verified.manifest.dossier} (restauré)",
          "PARTIDUO_LOCAL_DATABASE" => database,
        }
        env["PARTIDUO_ASSETS_ROOT"] = File.join(home.root, "assets") unless Programs.installed_assets?
        begin
          dossier.save(env)
          backups.restore(verified, identity, dossier)
          Programs.run!("partiduo-manage", ["migrate"], env, echo: false)
          Backups.active_modules(env).try { |modules| env["PARTIDUO_MODULES"] = modules }
          collect_assets(env)
          dossier.save(env)
        rescue ex
          STDERR.puts "partiduo : restauration interrompue, base et répertoire retirés"
          Postgres.dropdb(database) rescue nil
          FileUtils.rm_rf(dossier.dir)
          raise ex
        end
      end

      private def self.existing(home : Home, names : Array(String)) : Dossier
        raise Error.new("un nom de dossier attendu") unless names.size == 1
        name = names.first
        raise Error.new("nom de dossier refusé : #{name}") unless Local.valid_name?(name)
        dossier = home.dossier(name)
        raise Error.new("dossier #{name} introuvable (partiduo dossier liste)") unless dossier.exists?
        dossier
      end
    end
  end
end
