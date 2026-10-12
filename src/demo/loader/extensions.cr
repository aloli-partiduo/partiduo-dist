# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDist
  module Demo
    class Loader
      # --- Extensions : plateforme agréée, TELEDEC, CRM, modèles -------------------

      def execute(operation : Format::SynchronisationPlateforme, day : Time) : Nil
        ok(Einvoicing::Api.synchronize(actor), "synchronisation avec la plateforme")
      end

      # Télédéclarations préparées, contrôlées, transmises au TELEDEC simulé
      # puis accusées.
      def execute(operation : Format::Teledeclarations, day : Time) : Nil
        operation.declarations.each do |declaration|
          input = teledec_input(declaration) || next
          filing = ok(Teledec::Api.prepare(actor, input), "télédéclaration #{input.kind}")
          ok(Teledec::Api.check(actor, filing.id), "contrôle de #{input.kind}")
          ok(Teledec::Api.transmit(actor, filing.id), "transmission de #{input.kind} au TELEDEC simulé")
          ok(Teledec::Api.refresh(actor, filing.id), "accusé de #{input.kind}")
        end
      end

      private def teledec_input(declaration : Format::DeclarationTeledec) : Teledec::Api::PrepareInput?
        if text = declaration.exercice
          Teledec::Api::PrepareInput.new(declaration.nature, fiscal_year_id: fiscal_year(dates.year(text)).id)
        elsif text = declaration.annee
          Teledec::Api::PrepareInput.new(declaration.nature, year: dates.year(text))
        elsif text = declaration.derniere_de
          vat = Acc.vat_returns(actor, "fr_ca3", dates.year(text)).max_by? { |item| item.id || 0_i64 } || return
          Teledec::Api::PrepareInput.new(declaration.nature, vat_return_id: vat.id)
        else
          raise LoadError.new("télédéclaration #{declaration.nature} : exercice, annee ou derniere_de attendu")
        end
      end

      # Relation client (`crm.yml`) : organisations, contacts (opposition
      # comprise), opportunités à toutes les étapes, devis tiré d'une
      # opportunité, activités datées autour du jour du chargement.
      def execute(operation : Format::CrmOperation, day : Time) : Nil
        crm = dossier.parse(Format::CrmFile, operation.fichier)
        ::Crm::Defaults.ensure!
        crm.organisations.each do |item|
          input = ::Crm::Api::OrganizationInput.new(name: item.nom, nature: item.nature, siren: item.siren, city: item.ville,
            country_code: item.pays, source_id: crm_source(item.origine), owner_id: user_id(item.responsable))
          @crm_refs["organisation:#{item.ref}"] = ok(::Crm::Api.create_organization(actor, input), "organisation #{item.nom}").id
        end
        crm.contacts.each { |item| crm_contact(item) }
        crm.opportunites.each { |item| crm_opportunity(item) }
        crm.activites.each do |item|
          input = ::Crm::Api::ActivityInput.new(kind: item.genre, subject: item.objet, due_on: dates.date(item.echeance),
            owner_id: user_id(item.responsable), opportunity_id: item.opportunite.try { |ref| crm_ref("opportunite", ref) },
            organization_id: item.organisation.try { |ref| crm_ref("organisation", ref) })
          ok(::Crm::Api.create_activity(actor, input), "activité #{item.objet}")
        end
      end

      # Identifiants des organisations, contacts et opportunités de `crm.yml`.
      @crm_refs = {} of String => Int64

      private def crm_ref(kind : String, ref : String) : Int64
        @crm_refs["#{kind}:#{ref}"]? || raise LoadError.new("#{kind} « #{ref} » absent de crm.yml")
      end

      private def crm_contact(item : Format::Contact) : Nil
        input = ::Crm::Api::ContactInput.new(last_name: item.nom, first_name: item.prenom,
          organization_id: item.organisation.try { |ref| crm_ref("organisation", ref) }, civility: item.civilite || "",
          job_title: item.fonction || "", email: item.courriel || "", legal_basis: item.base_legale,
          source_id: item.origine.try { |code| crm_source(code) })
        contact = ok(::Crm::Api.create_contact(actor, input), "contact #{item.prenom} #{item.nom}")
        @crm_refs["contact:#{item.ref}"] = contact.id
        item.opposition.try { |reason| ok(::Crm::Api.record_opposition(actor, contact.id, reason), "opposition") }
      end

      # Opportunité créée à son étape (« Négociation » pour une affaire
      # gagnée ou perdue, déplacée ensuite) ; devis brouillon tiré de
      # l'opportunité si demandé : le prospect devient client.
      private def crm_opportunity(item : Format::Opportunite) : Nil
        closed = item.etape.in?("won", "lost")
        input = ::Crm::Api::OpportunityInput.new(title: item.titre, organization_id: crm_ref("organisation", item.organisation),
          contact_id: item.contact.try { |ref| crm_ref("contact", ref) }, amount: d(item.montant),
          expected_close_on: dates.date(item.cloture_prevue), owner_id: user_id(item.responsable),
          stage_id: crm_stage(closed ? "negotiation" : item.etape), source_id: item.origine.try { |code| crm_source(code) })
        id = ok(::Crm::Api.create_opportunity(actor, input), "opportunité #{item.titre}").id
        item.ref.try { |ref| @crm_refs["opportunite:#{ref}"] = id }
        if item.etape == "won"
          ok(::Crm::Api.move_opportunity(actor, id, ::Crm::Api::MoveInput.new(crm_stage("won"))), "opportunité gagnée")
        elsif item.etape == "lost"
          loss = item.perte || raise LoadError.new("opportunité perdue sans motif : #{item.titre}")
          reason = ::Crm::Api.loss_reasons(system).find(&.code.==(loss.motif)) || raise LoadError.new("motif de perte #{loss.motif} inconnu")
          ok(::Crm::Api.move_opportunity(actor, id, ::Crm::Api::MoveInput.new(crm_stage("lost"), reason.id, loss.commentaire)),
            "opportunité perdue")
        end
        ok(::Crm::Api.create_quote(actor, id), "devis depuis l'opportunité") if item.devis?
      end

      private def crm_stage(code : String) : Int64
        (::Crm::Api.stages(system).find(&.code.==(code)) || raise LoadError.new("étape CRM #{code} inconnue")).id
      end

      private def crm_source(code : String) : Int64
        (::Crm::Api.sources(system).find(&.code.==(code)) || raise LoadError.new("origine CRM #{code} inconnue")).id
      end

      # Modèles de factures de départ (chaque nature, chaque format) chargés
      # et activés, celui du format `defaut` par défaut ; rendu de la
      # dernière facture si demandé.
      def execute(operation : Format::ModelesOperation, day : Time) : Nil
        locale = operation.langue
        starters = Modeles::Config::KINDS.flat_map { |kind| Modeles::Config::FORMATS.map { |format| {kind, format} } }
        starters.each do |(kind, format)|
          name = "#{I18n.with_locale(locale) { I18n.t("modeles.kinds.#{kind}") }} — #{I18n.t("modeles.formats.#{format}")}"
          view = ok(Modeles::Api.upload(actor, Modeles::Api::UploadInput.new(filename: Modeles::Starters.filename(kind, locale, format),
            content: Modeles::Starters.file(kind, locale, format), name: name, kind: kind, locale: locale)), "modèle #{name}")
          ok(Modeles::Api.activate(actor, view.id), "activation du modèle #{name}")
          ok(Modeles::Api.set_default(actor, view.id), "modèle par défaut #{name}") if format == operation.defaut
        end
        return unless operation.rendre_derniere_facture?
        Inv.documents(actor, Inv::DocumentQuery.new(kind: "invoice", limit: 1)).first?.try do |invoice|
          pdf = operation.defaut.try { |format| Modeles::Converters.available?(format) } || false
          ok(Modeles::Api.render(actor, invoice.id, pdf: pdf), "rendu de #{invoice.number} avec le modèle par défaut")
        end
      end
    end
  end
end
