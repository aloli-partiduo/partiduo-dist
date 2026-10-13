# SPDX-License-Identifier: AGPL-3.0-or-later

require "json"
require "base64"
require "partiduo-backup"
require "./home"
require "./tools"

module PartiduoDist
  module Local
    alias Crypto = PartiduoBackup::Crypto

    # Sauvegardes d'un dossier local, au format des serveurs (D-LOC-006,
    # shard partiduo-backup) : fichiers `age` pour une clé de sauvegarde
    # tirée pour chaque sauvegarde, capsule chiffrée pour les clés de
    # l'utilisateur (il tient ici le rôle de l'exploitant), manifeste signé
    # par la clé du poste, stockage en écriture unique
    # `<poste>/<dossier>/<fichier>`. Une sauvegarde prise ici se restaure sur
    # un serveur, et inversement.
    class Backups
      getter home : Home

      def initialize(@home : Home)
      end

      # Clés publiques (`age1pq1…`) pour lesquelles les capsules sont
      # chiffrées : celles de l'utilisateur.
      def recipients_path : String
        File.join(home.root, "cles.recipients")
      end

      # Clé de signature du poste, créée à la première sauvegarde.
      def signing_key_path : String
        File.join(home.root, "backup-signing.key")
      end

      def default_store : String
        File.join(home.root, "sauvegardes")
      end

      # Nom du poste dans les emplacements et les manifestes.
      def self.station : String
        name = ::System.hostname.split('.').first.downcase.gsub(/[^a-z0-9-]/, '-').gsub(/-+/, '-').strip('-')
        PartiduoBackup::Locator.valid_server?(name) ? name : "poste"
      end

      def add_recipient(line : String) : String
        recipient = line.strip
        raise Error.new("clé publique refusée : une ligne age1pq1… attendue (age-keygen -y)") unless Crypto.valid_recipient?(recipient)
        current = File.exists?(recipients_path) ? File.read_lines(recipients_path).map(&.strip) : [] of String
        unless current.includes?(recipient)
          Dir.mkdir_p(home.root, 0o700)
          File.write(recipients_path, (current.reject(&.empty?) + [recipient]).join('\n') + "\n", perm: 0o644)
        end
        Crypto.recipient_fingerprint(recipient)
      end

      def recipients : Array(String)
        unless File.exists?(recipients_path)
          raise Error.new("aucune clé de sauvegarde : créez la vôtre puis déclarez sa clé publique :\n" \
                          "  age-keygen -pq | age -p > ~/partiduo-cle.age\n" \
                          "  age -d ~/partiduo-cle.age | age-keygen -y | partiduo cle ajouter -")
        end
        Crypto.read_recipients(recipients_path)
      rescue ex : Crypto::Error
        raise Error.new(ex.message.to_s)
      end

      def signing_public_line : String
        unless File.exists?(signing_key_path)
          Crypto::Signature.generate(signing_key_path, Backups.station)
        end
        Crypto::Signature.public_line(signing_key_path)
      end

      # --- Sauvegarde ---------------------------------------------------------

      record Result, locator : PartiduoBackup::Locator, store : String, files : Array(String)

      def take(dossier : Dossier, store_dir : String = default_store, prefix : String = "backup") : Result
        keys = recipients
        station = Backups.station
        public_line = signing_public_line
        env = dossier.env
        stamp = Time.utc.to_s("%Y%m%dT%H%M%SZ")
        stem = "#{prefix}-#{stamp}"
        work = File.join(dossier.dir, "preparation")
        FileUtils.rm_rf(work)
        Dir.mkdir_p(work, 0o700)
        key = Crypto.keygen
        dump = File.join(work, "#{stem}.dump.age")
        media = File.join(work, "#{stem}.media.tar.gz.age")
        database = dossier.database
        Postgres.check!(database)
        Dir.mkdir_p(dossier.media_dir, 0o700)
        begin
          code, errors = PartiduoBackup::Pipe.seal(dump, key.recipient) do |io|
            PartiduoBackup::Pipe.drain(io, [Postgres.tool("pg_dump"), "-Fc", "--no-owner", database], {"PGHOST" => Postgres.socket})
          end
          raise Error.new("pg_dump (code #{code}) : #{errors.strip.lines.first?}") unless code == 0
          code, errors = PartiduoBackup::Pipe.seal(media, key.recipient) do |io|
            PartiduoBackup::Pipe.drain(io, ["tar", "-C", dossier.media_dir, "-czf", "-", "."])
          end
          raise Error.new("tar (code #{code}) : #{errors.strip.lines.first?}") unless code == 0
          # Relue tout de suite, la clé de sauvegarde encore en main
          # (D-CHF-017).
          check_readable(dump, key.identity, [Postgres.tool("pg_restore"), "--list"])
          check_readable(media, key.identity, ["tar", "-tzf", "-"])
          capsule = File.join(work, "#{stem}#{Crypto::CAPSULE_AGE}")
          File.write(capsule, Crypto.capsule_for(key.identity, keys), perm: 0o640)
          entries = [dump, media].map do |path|
            Crypto::Entry.new(File.basename(path), File.size(path).to_i64, Digest::SHA256.new.file(path).hexfinal)
          end
          text = Crypto::Manifest.new(station, dossier.name, stem, Time.parse(stamp, "%Y%m%dT%H%M%SZ", Time::Location::UTC),
            "exploitation", key.recipient, keys.map { |recipient| Crypto.recipient_fingerprint(recipient) }, "",
            entries).to_s
          manifest = File.join(work, "#{stem}#{Crypto::MANIFEST}")
          File.write(manifest, text, perm: 0o640)
          File.write(File.join(work, "#{stem}#{Crypto::SIGNATURE}"), Crypto::Signature.sign(text, signing_key_path), perm: 0o640)
          root = PartiduoBackup::StoreRoot.new(store_dir, station)
          Dir.mkdir_p(store_dir, 0o700)
          sent = [dump, media, capsule, manifest, File.join(work, "#{stem}#{Crypto::SIGNATURE}")]
          sent.each do |path|
            locator = PartiduoBackup::Locator.new(station, dossier.name, File.basename(path))
            sha = File.open(path, "rb") { |file| root.put(locator, file, File.size(path).to_i64) }
            raise Error.new("#{locator} altéré à l'écriture") unless sha == Digest::SHA256.new.file(path).hexfinal
          end
          locator = PartiduoBackup::Locator.new(station, dossier.name, File.basename(dump))
          Result.new(locator, store_dir, sent.map { |path| File.basename(path) })
        rescue ex : Crypto::Error | PartiduoBackup::StoreRoot::Error
          raise Error.new(ex.message.to_s)
        ensure
          FileUtils.rm_rf(work)
        end
      end

      private def check_readable(path : String, identity : String, argv : Array(String)) : Nil
        result, _, age = PartiduoBackup::Pipe.unseal(path, identity) { |io| PartiduoBackup::Pipe.feed(io, argv) }
        unless result[0] == 0 && age == 0
          raise Error.new("#{File.basename(path)} illisible à sa prise : #{result[1].strip.lines.first?}")
        end
      end

      # --- Restauration -------------------------------------------------------

      # Sauvegarde d'un dossier `source` dans le stockage : `stem` donné, ou
      # la plus récente (tous postes et serveurs confondus).
      def find(store_dir : String, source : String, stem : String? = nil) : PartiduoBackup::Locator
        raise Error.new("stockage introuvable : #{store_dir}") unless Dir.exists?(store_dir)
        root = PartiduoBackup::StoreRoot.new(store_dir, Backups.station)
        dumps = root.list(source).select { |locator| locator.name.ends_with?(".dump.age") }
        dumps.select! { |locator| locator.stem == stem } if stem
        dumps.max_by?(&.taken_at) || raise Error.new("aucune sauvegarde chiffrée de #{source} dans #{store_dir}" \
                                                     "#{stem ? " (#{stem})" : ""}")
      rescue ex : PartiduoBackup::StoreRoot::Error
        raise Error.new(ex.message.to_s)
      end

      record Verified, locator : PartiduoBackup::Locator, manifest : Crypto::Manifest, dump : String, media : String,
        capsule : String

      # Manifeste authentifié (clé de ce poste, ou d'un serveur listée dans
      # `signers`), fichiers conformes au manifeste.
      def verify(store_dir : String, locator : PartiduoBackup::Locator, signers : Array(String)) : Verified
        root = PartiduoBackup::StoreRoot.new(store_dir, Backups.station)
        path = ->(suffix : String) { root.path(locator.sibling(suffix)) }
        text = File.read(path.call(Crypto::MANIFEST))
        signature = File.read(path.call(Crypto::SIGNATURE))
        allowed = signers + [Crypto::Signature.allowed_signer(Backups.station, signing_public_line)]
        unless Crypto::Signature.verify(text, signature, allowed, locator.server, locator.taken_at)
          raise Error.new("signature du manifeste refusée (#{locator.server}) : sauvegarde non authentique ; pour une " \
                          "sauvegarde d'un serveur, --signataires (lignes allowed_signers de ses clés)")
        end
        manifest = Crypto::Manifest.parse(text)
        unless manifest.server == locator.server && manifest.dossier == locator.slug && manifest.backup == locator.stem
          raise Error.new("manifeste d'une autre sauvegarde : #{locator}")
        end
        dump = path.call(".dump.age")
        media = path.call(".media.tar.gz.age")
        {dump, media}.each do |file|
          entry = manifest.file?(File.basename(file)) || raise Error.new("#{File.basename(file)} absent du manifeste")
          unless entry.size == File.size(file) && entry.sha256 == Digest::SHA256.new.file(file).hexfinal
            raise Error.new("empreinte de #{File.basename(file)} altérée : différente du manifeste signé")
          end
        end
        Verified.new(locator, manifest, dump, media, path.call(Crypto::CAPSULE_AGE))
      rescue ex : Crypto::Error | File::Error
        raise Error.new("sauvegarde #{locator} : #{ex.message}")
      end

      # Clé de la sauvegarde, sortie de sa capsule par la clé de
      # l'utilisateur (`age` demande sa phrase de passe sur le terminal).
      def open_capsule(verified : Verified, identity_file : String) : String
        raise Error.new("capsule absente : #{verified.capsule}") unless File.exists?(verified.capsule)
        opened = IO::Memory.new
        status = Process.run(Crypto.tool("age"), ["-d", "-i", identity_file, verified.capsule],
          input: Process::Redirect::Inherit, output: opened, error: Process::Redirect::Inherit)
        raise Error.new("capsule non ouverte par cette clé (#{identity_file})") unless status.success?
        identity = opened.to_s.strip
        unless Crypto.recipient_of(identity) == verified.manifest.recipient
          raise Error.new("la capsule ne contient pas la clé de cette sauvegarde")
        end
        identity
      end

      # Base et pièces jointes du dossier remplacées par la sauvegarde ; tout
      # est authentifié avant le premier geste.
      def restore(verified : Verified, identity : String, dossier : Dossier) : Nil
        PartiduoBackup::Pipe.verify(verified.dump, identity)
        PartiduoBackup::Pipe.verify(verified.media, identity)
        database = dossier.database
        Postgres.dropdb(database)
        Postgres.createdb(database)
        result, _, age = PartiduoBackup::Pipe.unseal(verified.dump, identity) do |io|
          PartiduoBackup::Pipe.feed(io, [Postgres.tool("pg_restore"), "--no-owner", "--exit-on-error", "-d", database],
            {"PGHOST" => Postgres.socket})
        end
        raise Error.new("pg_restore (code #{result[0]}) : #{result[1].strip.lines.first?}") unless result[0] == 0 && age == 0
        FileUtils.rm_rf(dossier.media_dir)
        Dir.mkdir_p(dossier.media_dir, 0o700)
        result, _, age = PartiduoBackup::Pipe.unseal(verified.media, identity) do |io|
          PartiduoBackup::Pipe.feed(io, ["tar", "-C", dossier.media_dir, "-xzf", "-"])
        end
        raise Error.new("tar (code #{result[0]}) : #{result[1].strip.lines.first?}") unless result[0] == 0 && age == 0
      rescue ex : Crypto::Error
        raise Error.new(ex.message.to_s)
      end

      # Modules et extensions actifs dans la base restaurée
      # (`partiduo-manage instance status`), pour `PARTIDUO_MODULES`.
      def self.active_modules(env : Hash(String, String)) : String?
        code, output = Programs.run("partiduo-manage", ["instance", "status"], env, echo: false)
        return unless code == 0
        line = output.lines.reverse.find(&.starts_with?('{')) || return
        pieces = JSON.parse(line)["data"]["modules"].as_a
        codes = pieces.select { |piece| piece["active"]?.try(&.as_bool?) && piece["kind"]?.try(&.as_s?) != "socle" }
          .compact_map { |piece| piece["code"]?.try(&.as_s?).try(&.downcase) }
        codes.empty? ? nil : codes.join(',')
      rescue JSON::ParseException | KeyError | TypeCastError
        nil
      end
    end
  end
end
