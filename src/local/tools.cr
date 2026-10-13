# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Local
    # Programmes de la distribution (`partiduo-manage`, `partiduo-server`),
    # installés à côté de `partiduo` ; `PARTIDUO_DIST_BIN` les désigne
    # ailleurs (développement : `bin/` de partiduo-dist).
    module Programs
      def self.dir : String
        ENV["PARTIDUO_DIST_BIN"]?.presence ||
          Process.executable_path.try { |path| File.dirname(path) } || "."
      end

      def self.path(name : String) : String
        program = File.join(dir, name)
        unless File::Info.executable?(program)
          raise Error.new("#{name} introuvable dans #{dir} (PARTIDUO_DIST_BIN pour un autre répertoire)")
        end
        program
      end

      # Fichiers statiques collectés à l'installation du paquet, à côté des
      # programmes ; sinon (développement), ils sont collectés dans le
      # répertoire de l'utilisateur.
      def self.installed_assets? : Bool
        Dir.exists?(File.join(dir, "..", "share", "partiduo", "assets"))
      end

      # Lance un programme avec l'environnement du dossier ; rend le code de
      # sortie et la sortie, qui est aussi recopiée sur celle de `partiduo`
      # quand `echo` est vrai.
      def self.run(name : String, args : Array(String), env : Hash(String, String), echo : Bool = true) : {Int32, String}
        output = IO::Memory.new
        target = echo ? IO::MultiWriter.new(output, STDOUT) : output
        status = Process.run(path(name), args, env: env, output: target, error: echo ? STDERR : target)
        {status.exit_code? || -1, output.to_s}
      end

      def self.run!(name : String, args : Array(String), env : Hash(String, String), echo : Bool = true) : String
        code, output = run(name, args, env, echo)
        raise Error.new("#{name} #{args.first?} : échec (code #{code})") unless code == 0
        output
      end
    end

    # PostgreSQL du poste, par ses outils (`createdb`, `dropdb`, `psql`),
    # pris dans le PATH ou dans `PARTIDUO_PG_BIN` ; socket : `PGHOST`, sinon
    # `/tmp`.
    module Postgres
      DATABASE = /\A[a-z_][a-z0-9_]{0,62}\z/

      def self.socket : String
        ENV["PGHOST"]?.presence || "/tmp"
      end

      def self.database_url(database : String) : String
        "postgres:///#{database}?host=#{socket}"
      end

      def self.tool(name : String) : String
        if dir = ENV["PARTIDUO_PG_BIN"]?.presence
          File.join(dir, name)
        else
          Process.find_executable(name) ||
            raise Error.new("#{name} introuvable : installez PostgreSQL (Postgres.app ou Homebrew sur macOS, " \
                            "pkg install postgresql17-server sur FreeBSD) ou indiquez PARTIDUO_PG_BIN")
        end
      end

      def self.run(name : String, args : Array(String)) : {Int32, String, String}
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run(tool(name), args, env: {"PGHOST" => socket}, output: output, error: error)
        {status.exit_code? || -1, output.to_s, error.to_s}
      end

      def self.check!(database : String) : Nil
        raise Error.new("nom de base invalide : #{database}") unless DATABASE.matches?(database)
      end

      def self.exists?(database : String) : Bool
        check!(database)
        code, output, error = run("psql", ["-X", "-d", "postgres", "-tAc",
                                           "SELECT 1 FROM pg_database WHERE datname = '#{database}'"])
        unless code == 0
          raise Error.new("PostgreSQL injoignable (socket #{socket}) : #{error.strip.lines.first?} — " \
                          "démarrez PostgreSQL, ou indiquez son socket par PGHOST")
        end
        output.strip == "1"
      end

      def self.createdb(database : String) : Nil
        check!(database)
        code, _, error = run("createdb", ["--encoding=UTF8", database])
        raise Error.new("createdb #{database} : #{error.strip.lines.first?}") unless code == 0
      end

      def self.dropdb(database : String) : Nil
        check!(database)
        code, _, error = run("dropdb", ["--if-exists", database])
        raise Error.new("dropdb #{database} : #{error.strip.lines.first?}") unless code == 0
      end
    end
  end
end
