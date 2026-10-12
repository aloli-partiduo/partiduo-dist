# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    # Dossier de démonstration lu dans `<source>/<code>/` : `dossier.yml`,
    # `referentiel.yml`, `parametres.yml`, `operations.yml`, `attendus.yml`,
    # et les fichiers qu'ils citent (`crm.yml`, relevés). Toute erreur de
    # lecture cite le fichier.
    class Dossier
      FILES = %w[dossier referentiel parametres operations attendus]

      getter directory : String
      getter identity : Format::DossierFile
      getter reference : Format::Referentiel
      getter parameters : Format::Parametres
      getter operations : Format::OperationsFile
      getter expected : Format::Attendus

      def self.read(source : String, code : String) : Dossier
        raise LoadError.new("code de dossier invalide : « #{code} »") unless code.matches?(/\A[a-z][a-z0-9_-]*\z/)
        directory = File.join(source, code)
        raise LoadError.new("dossier introuvable : #{directory}") unless Dir.exists?(directory)
        new(directory)
      end

      def initialize(@directory : String)
        @identity = parse(Format::DossierFile, "dossier.yml")
        @reference = parse(Format::Referentiel, "referentiel.yml")
        @parameters = parse(Format::Parametres, "parametres.yml")
        @operations = parse(Format::OperationsFile, "operations.yml")
        @expected = parse(Format::Attendus, "attendus.yml")
        expected_code = File.basename(@directory)
        unless @identity.code == expected_code
          raise LoadError.new("dossier.yml : code « #{@identity.code} » différent du répertoire « #{expected_code} »")
        end
      end

      def code : String
        identity.code
      end

      # Fichier de données du dossier, lu puis vérifié (`format: 1`).
      def parse(type : T.class, name : String) : T forall T
        path = path(name)
        raise LoadError.new("fichier absent : #{path}") unless File.exists?(path)
        value = begin
          File.open(path) { |io| type.from_yaml(io) }
        rescue ex : YAML::ParseException
          raise LoadError.new("#{path} : #{ex.message}")
        end
        unless value.format == Format::VERSION
          raise LoadError.new("#{path} : format #{value.format} inconnu (attendu : #{Format::VERSION})")
        end
        value
      end

      # Chemin d'un fichier du dossier ; refuse de sortir du répertoire.
      def path(name : String) : String
        if name.starts_with?('/') || name.split('/').includes?("..")
          raise LoadError.new("chemin refusé : « #{name} »")
        end
        File.join(@directory, name)
      end

      def read_bytes(name : String) : Bytes
        path = path(name)
        raise LoadError.new("fichier absent : #{path}") unless File.exists?(path)
        File.read(path).to_slice
      end

      # Valeur de `PARTIDUO_MODULES` pour ce dossier.
      def active_codes : String
        (identity.modules + identity.extensions).join(",")
      end

      def extension?(code : String) : Bool
        identity.extensions.includes?(code)
      end

      def siren : String
        identity.societe.siren.to_s.delete(' ')
      end

      def host(domain : String) : String
        "#{code}.#{domain}"
      end

      def party(code : String) : Format::Tiers
        reference.tiers.find(&.code.==(code)) || raise LoadError.new("tiers #{code} absent du référentiel")
      end

      def item(code : String) : Format::Article
        reference.articles.find(&.code.==(code)) || raise LoadError.new("article #{code} absent du référentiel")
      end

      # Structures publiques du référentiel (clients de nature `public`
      # dotés d'un SIRET), pour le Chorus Pro simulé.
      def public_structures : Array({String, String})
        reference.tiers.compact_map do |party|
          siret = party.siret
          {siret, party.nom.to_s} if party.customer? && party.nature == "public" && siret
        end
      end
    end
  end
end
