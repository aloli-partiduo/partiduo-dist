# SPDX-License-Identifier: AGPL-3.0-or-later

require "file_utils"
require "random/secure"
require "socket"

module PartiduoDist
  # Dossiers locaux, sans serveur (commande `partiduo`) : chaque dossier a sa
  # base dans le PostgreSQL du poste et son répertoire de données
  # (réglages, pièces jointes, journal du serveur), servi en
  # `http://<dossier>.partiduo.localhost:<port>/` à l'utilisateur seul.
  module Local
    # Refus ou échec, avec un message pour l'utilisateur.
    class Error < Exception
    end

    # Nom d'un dossier : même règle que le sous-domaine d'une instance.
    NAME     = /\A[a-z][a-z0-9-]{0,39}\z/
    RESERVED = %w[admin www]
    DOMAIN   = "partiduo.localhost"
    # Premier port essayé ; chaque dossier garde le sien.
    FIRST_PORT = 8400
    LAST_PORT  = 8999

    def self.valid_name?(name : String) : Bool
      NAME.matches?(name) && !name.ends_with?('-') && !RESERVED.includes?(name)
    end

    # Base d'un dossier local : préfixe propre, jamais celui d'une instance
    # de serveur (`partiduo_<dossier>`) ni d'une démonstration.
    def self.database_for(name : String) : String
      "partiduo_local_#{name.tr("-", "_")}"
    end

    def self.host_for(name : String) : String
      "#{name}.#{DOMAIN}"
    end

    # Lien d'invitation affiché par `partiduo-manage provision`
    # (`https://<hôte>/invitation/<jeton>`), réécrit pour le dossier local.
    def self.invitation_url(output : String, name : String, port : Int32) : String?
      token = output.match(/\/invitation\/([A-Za-z0-9_\-]+)/).try(&.[1]) || return
      "http://#{host_for(name)}:#{port}/invitation/#{token}"
    end

    # Répertoire de l'utilisateur : `PARTIDUO_HOME`, sinon
    # `$XDG_DATA_HOME/partiduo`, sinon `~/.local/share/partiduo`.
    class Home
      getter root : String

      def initialize(@root : String = Home.default_root)
      end

      def self.default_root : String
        ENV["PARTIDUO_HOME"]?.presence ||
          File.join(ENV["XDG_DATA_HOME"]?.presence || File.join(Path.home.to_s, ".local", "share"), "partiduo")
      end

      def dossiers_dir : String
        File.join(root, "dossiers")
      end

      def dossier(name : String) : Dossier
        Dossier.new(name, File.join(dossiers_dir, name))
      end

      def dossiers : Array(Dossier)
        return [] of Dossier unless Dir.exists?(dossiers_dir)
        Dir.children(dossiers_dir).sort.compact_map do |name|
          dossier = dossier(name)
          dossier if Local.valid_name?(name) && dossier.exists?
        end
      end

      # Port libre : ni pris par un autre dossier, ni occupé sur le poste.
      def free_port(taken : Array(Int32) = dossiers.compact_map(&.port?)) : Int32
        (FIRST_PORT..LAST_PORT).each do |port|
          next if taken.includes?(port)
          return port if Local.port_free?(port)
        end
        raise Error.new("aucun port libre entre #{FIRST_PORT} et #{LAST_PORT}")
      end
    end

    def self.port_free?(port : Int32) : Bool
      server = TCPServer.new("127.0.0.1", port)
      server.close
      true
    rescue Socket::BindError
      false
    end

    def self.listening?(port : Int32) : Bool
      TCPSocket.new("127.0.0.1", port, connect_timeout: 1.second).close
      true
    rescue Socket::Error | IO::TimeoutError
      false
    end

    # Un dossier : ses réglages (`dossier.env`, variables d'environnement du
    # serveur, 0600 car la clé secrète y est), ses pièces jointes (`media/`),
    # le journal et le processus de son serveur.
    class Dossier
      getter name : String
      getter dir : String

      def initialize(@name : String, @dir : String)
      end

      def env_path : String
        File.join(dir, "dossier.env")
      end

      def media_dir : String
        File.join(dir, "media")
      end

      def log_path : String
        File.join(dir, "serveur.log")
      end

      def pid_path : String
        File.join(dir, "serveur.pid")
      end

      def exists? : Bool
        File.exists?(env_path)
      end

      def env : Hash(String, String)
        Dossier.parse_env(File.read(env_path))
      rescue File::Error
        raise Error.new("dossier #{name} introuvable (#{env_path})")
      end

      def save(values : Hash(String, String)) : Nil
        Dir.mkdir_p(dir, 0o700)
        partial = "#{env_path}.part"
        File.write(partial, Dossier.dump_env(values), perm: 0o600)
        File.rename(partial, env_path)
      end

      def port? : Int32?
        env["PORT"]?.try(&.to_i?)
      rescue Error
        nil
      end

      def port : Int32
        port? || raise Error.new("dossier #{name} : port absent de #{env_path}")
      end

      def url : String
        "http://#{Local.host_for(name)}:#{port}/"
      end

      def label : String
        env["PARTIDUO_LOCAL_NAME"]? || ""
      end

      def database : String
        env["PARTIDUO_LOCAL_DATABASE"]? || Local.database_for(name)
      end

      # Processus du serveur, s'il tourne encore (un fichier laissé par un
      # serveur arrêté est ignoré).
      def pid : Int64?
        value = File.read(pid_path).strip.to_i64? rescue nil
        value if value && Process.exists?(value)
      end

      def open? : Bool
        !pid.nil?
      end

      # `CLÉ=valeur` par ligne ; lignes vides et commentaires ignorés.
      def self.parse_env(text : String) : Hash(String, String)
        values = {} of String => String
        text.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?('#')
          key, sep, value = line.partition('=')
          values[key] = value unless sep.empty? || key.empty?
        end
        values
      end

      def self.dump_env(values : Hash(String, String)) : String
        String.build do |io|
          io << "# Dossier local Partiduo (commande partiduo) : réglages du serveur.\n"
          values.keys.sort.each do |key|
            value = values[key]
            raise Error.new("réglage #{key} sur plusieurs lignes") if value.includes?('\n')
            io << key << '=' << value << '\n'
          end
        end
      end
    end

    def self.secret_key : String
      Random::Secure.hex(48)
    end
  end
end
