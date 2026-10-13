# SPDX-License-Identifier: AGPL-3.0-or-later

# Dossier local, sans serveur (`MARTEN_ENV=local`, commande `partiduo`) : un
# dossier sur le poste de son utilisateur, servi à lui seul, en
# `http://<dossier>.partiduo.localhost:<port>/`.
#
# Comme la production (pas de débogage, gabarits en cache, clé secrète
# obligatoire, fichiers statiques collectés), sauf :
# * écoute sur 127.0.0.1 seulement, jamais sur le réseau ;
# * HTTP : pas de proxy TLS devant, donc ni cookies `Secure` ni HSTS. Les
#   navigateurs tiennent `*.localhost` pour un contexte sécurisé ; les clés
#   d'accès y fonctionnent en HTTP (`origin_allowed?` du cœur) ;
# * hôtes admis : ceux de `localhost`.
Marten.configure :local do |config|
  config.debug = false
  config.host = "127.0.0.1"
  config.port = (ENV["PORT"]? || "8400").to_i
  config.secret_key = ENV.fetch("MARTEN_SECRET_KEY")
  config.allowed_hosts = ["127.0.0.1", "localhost", ".localhost"]

  config.sessions.cookie_http_only = true
  config.csrf.cookie_http_only = true
  config.templates.cached = true

  # Fichiers à côté des programmes installés, comme en production
  # (`production.cr` de ce répertoire) ; `PARTIDUO_ASSETS_ROOT` et
  # `PARTIDUO_ARTIFACTS_ROOT` restent prioritaires.
  share = Process.executable_path.try { |path| File.expand_path(File.join(File.dirname(path), "..", "share", "partiduo")) }
  artifacts = ENV["PARTIDUO_ARTIFACTS_ROOT"]? || share.try { |dir| File.join(dir, "artifacts") }
  config.root_path = artifacts if artifacts && Dir.exists?(artifacts)
  installed = share.try { |dir| File.join(dir, "assets") }
  config.assets.root = ENV["PARTIDUO_ASSETS_ROOT"]? || (installed if installed && Dir.exists?(installed)) || "assets"
  config.middleware = [Marten::Middleware::AssetServing] + config.middleware
end
