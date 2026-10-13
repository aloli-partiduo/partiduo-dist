# SPDX-License-Identifier: AGPL-3.0-or-later

require "spec"
require "../src/local/cli"

# Commande `partiduo` (dossiers locaux, sans serveur) : ce qui se vérifie
# sans PostgreSQL ni serveur. La création, l'ouverture et la suppression
# réelles s'essaient sur le poste (README, « Dossiers locaux »).

private alias Local = PartiduoDist::Local

private def scratch_home : Local::Home
  Local::Home.new(File.join(Dir.tempdir, "partiduo-local-spec-#{Random::Secure.hex(4)}"))
end

private def run_cli(home : Local::Home, args : Array(String)) : Int32
  Local::CLI.run(args, home)
end

describe PartiduoDist::Local do
  it "n'accepte que des noms de dossier sûrs, et en tire une base locale distincte" do
    %w[famille atelier-2 a].each { |name| Local.valid_name?(name).should be_true }
    ["", "Famille", "1foyer", "foyer-", "admin", "www", "a b", "../x", "x" * 41].each do |name|
      Local.valid_name?(name).should be_false
    end
    Local.database_for("atelier-2").should eq("partiduo_local_atelier_2")
    Local.host_for("famille").should eq("famille.partiduo.localhost")
  end

  it "réécrit le lien d'invitation du provisionnement pour le dossier local" do
    output = "Invitation pour moi@exemple.fr (jusqu'au 2026-10-20) : https://famille.partiduo.localhost/invitation/AbC-12_x\n"
    Local.invitation_url(output, "famille", 8401).should eq("http://famille.partiduo.localhost:8401/invitation/AbC-12_x")
    Local.invitation_url("rien", "famille", 8401).should be_nil
  end

  it "garde les réglages d'un dossier en 0600, triés, sans valeur sur plusieurs lignes" do
    home = scratch_home
    dossier = home.dossier("famille")
    dossier.save({"PORT" => "8401", "MARTEN_SECRET_KEY" => "secret", "PARTIDUO_LOCAL_NAME" => "Foyer Martin = nous"})
    (File.info(dossier.env_path).permissions.value & 0o077).should eq(0)
    dossier.env.should eq({"MARTEN_SECRET_KEY" => "secret", "PARTIDUO_LOCAL_NAME" => "Foyer Martin = nous", "PORT" => "8401"})
    File.read(dossier.env_path).lines.reject(&.starts_with?('#')).first.should start_with("MARTEN_SECRET_KEY=")
    dossier.port.should eq(8401)
    dossier.url.should eq("http://famille.partiduo.localhost:8401/")
    dossier.label.should eq("Foyer Martin = nous")
    expect_raises(Local::Error, /plusieurs lignes/) { dossier.save({"X" => "a\nb"}) }
    home.dossiers.map(&.name).should eq(["famille"])
    dossier.open?.should be_false
    File.write(dossier.pid_path, "999999\n")
    dossier.open?.should be_false
  end

  it "donne à chaque dossier un port à lui, libre sur le poste" do
    home = scratch_home
    first = home.free_port
    home.free_port([first]).should_not eq(first)
    busy = TCPServer.new("127.0.0.1", 0)
    begin
      Local.port_free?(busy.local_address.port).should be_false
      Local.listening?(busy.local_address.port).should be_true
    ensure
      busy.close
    end
  end
end

describe PartiduoDist::Local::CLI do
  it "refuse avant tout geste un nom invalide, une adresse absente, un dossier inconnu, une suppression non confirmée" do
    home = scratch_home
    run_cli(home, ["dossier", "creer", "Foyer", "--name", "x", "--admin-email", "a@b.fr"]).should eq(1)
    run_cli(home, ["dossier", "creer", "foyer", "--name", "Foyer"]).should eq(1)
    run_cli(home, ["dossier", "creer", "foyer", "--admin-email", "a@b.fr"]).should eq(1)
    run_cli(home, ["dossier", "creer", "foyer", "--name", "F", "--admin-email", "a@b.fr", "--kind", "asso"]).should eq(1)
    run_cli(home, ["dossier", "ouvrir", "inconnu"]).should eq(1)
    home.dossier("famille").save({"PORT" => "8401"})
    run_cli(home, ["dossier", "supprimer", "famille"]).should eq(1)
    run_cli(home, ["dossier", "supprimer", "famille", "--confirmer", "autre"]).should eq(1)
    home.dossier("famille").exists?.should be_true
    Dir.exists?(home.dossiers_dir).should be_true
    run_cli(home, ["dossier", "inconnue"]).should eq(64)
    run_cli(home, ["--version"]).should eq(0)
  end
end

describe PartiduoDist::Local::Backups do
  it "nomme le poste, n'accepte que des clés post-quantiques, refuse une sauvegarde sans clé déclarée" do
    home = scratch_home
    backups = Local::Backups.new(home)
    PartiduoBackup::Locator.valid_server?(Local::Backups.station).should be_true
    expect_raises(Local::Error, /aucune clé de sauvegarde/) { backups.recipients }
    expect_raises(Local::Error, /age1pq1/) { backups.add_recipient("age1qqqqqqqqqqqqqqqqqqqqqqqqqqqq") }
    recipient = PartiduoBackup::Crypto.keygen.recipient
    backups.add_recipient("#{recipient}\n").should eq(PartiduoBackup::Crypto.recipient_fingerprint(recipient))
    backups.add_recipient(recipient)
    backups.recipients.should eq([recipient])
    backups.signing_public_line.should start_with("ssh-ed25519 ")
    (File.info(backups.signing_key_path).permissions.value & 0o077).should eq(0)
    dossier = home.dossier("famille")
    dossier.save({"PORT" => "8401", "PARTIDUO_LOCAL_DATABASE" => "partiduo_local_famille"})
    expect_raises(Local::Error, /stockage introuvable/) { backups.find(File.join(home.root, "absent"), "famille") }
    Dir.mkdir_p(backups.default_store)
    expect_raises(Local::Error, /aucune sauvegarde chiffrée de famille/) { backups.find(backups.default_store, "famille") }
  end
end
