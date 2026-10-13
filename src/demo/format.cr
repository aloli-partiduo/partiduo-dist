# SPDX-License-Identifier: AGPL-3.0-or-later

require "yaml"

module PartiduoDist
  module Demo
    # Structures des fichiers d'un dossier de démonstration, format 1
    # (`doc/format-dossiers.adoc` de `partiduo-demo`). Les noms des champs
    # sont ceux du format, en français ; une clé inconnue est refusée.
    # Montants : chaînes décimales (`"1234.50"`), jamais des flottants.
    module Format
      VERSION = 1

      alias Quantity = Int32 | String

      module Strict
        macro included
          include YAML::Serializable
          include YAML::Serializable::Strict
        end
      end

      # --- dossier.yml -------------------------------------------------------------

      class Societe
        include Strict
        getter nom : String
        getter forme_juridique : String?
        getter capital : String?
        getter rcs : String?
        getter siren : String?
        getter tva : String?
        getter rue : String?
        getter numero : String?
        getter code_postal : String?
        getter ville : String?
        getter pays : String = "FR"
        getter telephone : String?
        getter courriel : String?
        getter regime : String = "fr"
        getter langue : String = "fr"
      end

      class Utilisateur
        include Strict
        getter email : String
        getter prenom : String
        getter nom : String
        getter profil : String = "ADMIN"
        getter role : String = "member"
      end

      class DossierFile
        include Strict
        getter format : Int32
        getter code : String
        getter profil : String
        getter type : String = "company"
        getter description : String = ""
        getter societe : Societe
        getter modules : Array(String)
        getter extensions : Array(String) = [] of String
        getter exercices : Array(String) = [] of String
        getter utilisateurs : Array(Utilisateur)
        getter parcours : Array(String) = [] of String
      end

      # --- referentiel.yml ---------------------------------------------------------

      class Compte
        include Strict
        getter numero : String
        getter libelle : String
        getter parent : String
      end

      class TauxTva
        include Strict
        getter code : String
        getter libelle : String
        getter taux : String
        getter categorie : String
        getter exoneration_code : String?
        getter exoneration_motif : String?
      end

      class Adresse
        include Strict
        getter ligne1 : String
        getter code_postal : String
        getter ville : String
        getter pays : String = "FR"
      end

      class Personne
        include Strict
        getter nom : String
        getter prenoms : String
        getter naissance : String?
        getter description : String?
      end

      class FacturationClient
        include Strict
        getter rythme : String
        getter encours_max : String?
      end

      class Tiers
        include Strict
        getter code : String
        getter categorie : String
        getter nom : String?
        getter nature : String?
        getter siren : String?
        getter siret : String?
        getter tva : String?
        getter courriel : String?
        getter adresse : Adresse?
        getter personne : Personne?
        getter facturation : FacturationClient?

        def customer? : Bool
          categorie == "client"
        end
      end

      class Article
        include Strict
        getter code : String
        getter categorie : String
        getter nom : String
        getter unite : String = "C62"
        getter prix_vente : String?
        getter prix_achat : String?
        getter taux : String?
        getter compte : String?
        getter? stock : Bool = false
        getter poste : String?
        getter nature_micro : String?
      end

      class Poste
        include Strict
        getter code : String
        getter description : String = ""
      end

      class PlanAnalytique
        include Strict
        getter nom : String
        getter description : String = ""
        getter postes : Array(Poste)
      end

      class Repartition
        include Strict
        getter pourcentage : String
        getter postes : Array(String)
      end

      class Cle
        include Strict
        getter nom : String
        getter description : String = ""
        getter journaux : Array(String) = [] of String
        getter repartition : Array(Repartition)
      end

      class Analytique
        include Strict
        getter plans : Array(PlanAnalytique) = [] of PlanAnalytique
        getter cles : Array(Cle) = [] of Cle
      end

      class Depot
        include Strict
        getter nom : String
        getter adresse : String = ""
        getter ville : String = ""
        getter pays : String = "FR"
        getter telephone : String = ""
        getter? defaut : Bool = false
      end

      class StockFile
        include Strict
        getter depots : Array(Depot) = [] of Depot
      end

      class Referentiel
        include Strict
        getter format : Int32
        getter comptes : Array(Compte) = [] of Compte
        getter taux_tva : Array(TauxTva) = [] of TauxTva
        getter tiers : Array(Tiers) = [] of Tiers
        getter articles : Array(Article) = [] of Article
        getter analytique : Analytique?
        getter stock : StockFile?
      end

      # --- parametres.yml ----------------------------------------------------------

      class JournalAchats
        include Strict
        getter compte_defaut : String
      end

      class ParamComptabilite
        include Strict
        getter journal_achats : JournalAchats?
      end

      class ParamFacturation
        include Strict
        getter tva_sur_debits : Bool?
        getter iban : String?
        getter bic : String?
        getter courriel_expediteur : String?
        getter nom_expediteur : String?
        getter taux_penalites : String?
        getter categorie_operation : String?
        getter delai_paiement : Int32?
        getter? envoi_automatique : Bool = false
      end

      class ParamAnalytique
        include Strict
        getter? ventilation_ventes : Bool = false
      end

      class ParamMicro
        include Strict
        getter periodicite : String
        getter debut_activite : String
        getter nature_defaut : String
      end

      class ParamLiberal
        include Strict
        getter profession : String
        getter debut_activite : String
        getter rubrique_defaut : String
      end

      # Service externe : toujours simulé en démonstration.
      class ParamPlateforme
        include Strict
        getter plateforme : String
        getter profil : String?
      end

      class ParamTeledec
        include Strict
        getter plateforme : String
        getter regime : String
        getter tva : String
        getter courriel : String
        getter siret : String
      end

      class Colonnes
        include Strict
        getter date : Int32
        getter libelle : Int32
        getter montant : Int32?
        getter debit : Int32?
        getter credit : Int32?
        getter information : Int32?
        getter reference : Int32?
        getter tiers : Int32?
      end

      class FormatCsv
        include Strict
        getter nom : String
        getter etablissement : String = ""
        getter journal : String = "banque"
        # Compte du journal financier (contrôle des soldes par le validateur).
        getter compte : String
        getter separateur : String = "semicolon"
        getter encodage : String = "utf-8"
        getter lignes_entete : Int32 = 1
        getter format_date : String = "dd/mm/yyyy"
        getter separateur_decimal : String = "comma"
        getter separateur_milliers : String = "none"
        getter? inverser : Bool = false
        getter colonnes : Colonnes
      end

      class Regle
        include Strict
        getter libelle_contient : String = ""
        getter montant : String?
        getter sens : String = "any"
        getter compte : String = ""
        getter tiers : String = ""
        getter position : Int32 = 100
      end

      class ParamBankimport
        include Strict
        getter formats : Array(FormatCsv) = [] of FormatCsv
        getter regles : Array(Regle) = [] of Regle
      end

      # Finances du foyer (extension PERSO, ADR-011) : membres, comptes du
      # foyer (repris d'un compte du plan ou créés), catégories propres,
      # étiquettes fiscales des catégories du plan.
      class MembrePerso
        include Strict
        getter email : String
        getter prenom : String
        getter role : String = "adult"
      end

      class ComptePerso
        include Strict
        getter nature : String
        getter libelle : String
        getter compte : String?
        getter etablissement : String = ""
        getter genre : String = ""
        getter taux : String?
        getter plafond : String?
        getter ouverture : String?
        getter titulaires : Array(String) = [] of String
        getter solde_ouverture : String?
      end

      class CategoriePerso
        include Strict
        getter libelle : String
        getter sens : String = "expense"
        getter parent : String?
        getter parent_compte : String?
        getter etiquette : String = ""
      end

      class EtiquettePerso
        include Strict
        getter compte : String
        getter etiquette : String
      end

      class ParamPerso
        include Strict
        getter membres : Array(MembrePerso) = [] of MembrePerso
        getter comptes : Array(ComptePerso) = [] of ComptePerso
        getter categories : Array(CategoriePerso) = [] of CategoriePerso
        getter etiquettes : Array(EtiquettePerso) = [] of EtiquettePerso
      end

      class Parametres
        include Strict
        getter format : Int32
        getter comptabilite : ParamComptabilite?
        getter facturation : ParamFacturation?
        getter analytique : ParamAnalytique?
        getter micro : ParamMicro?
        getter liberal : ParamLiberal?
        getter einv : ParamPlateforme?
        getter choruspro : ParamPlateforme?
        getter teledec : ParamTeledec?
        getter urssaf : ParamPlateforme?
        getter bankimport : ParamBankimport?
        getter perso : ParamPerso?
      end

      # --- operations.yml : éléments communs --------------------------------------

      # Condition d'exécution : opération jouée si sa date est postérieure
      # ou égale à `depuis` et antérieure à `avant`.
      class Condition
        include Strict
        getter depuis : String?
        getter avant : String?
      end

      class Reglement
        include Strict
        getter delai : Int32
        # `banque` : encaissement passé en banque et lettré ; `encaissement` :
        # règlement saisi en Facturation (recette au livre d'un micro).
        getter mode : String = "banque"
        getter moyen : String?
        getter libelle : String?
      end

      class Delai
        include Strict
        getter delai : Int32
      end

      class LigneEcriture
        include Strict
        getter compte : String
        getter debit : String?
        getter credit : String?
        getter tiers : String?
        getter libelle : String = ""
      end

      class LigneBanque
        include Strict
        getter compte : String?
        getter tiers : String?
        getter montant : String
        getter libelle : String = ""
      end

      class LigneStock
        include Strict
        getter article : String
        getter quantite : Quantity
        getter cout : String?
      end

      class LigneAchat
        include Strict
        getter article : String?
        getter quantite : Quantity?
        getter prix : String?
        getter compte : String?
        getter montant : String?
        getter taux : String?
        getter tva : String?
        getter libelle : String?
      end

      class LigneVente
        include Strict
        getter article : String
        getter quantite : Quantity
      end

      class LignePlateforme
        include Strict
        getter libelle : String
        getter quantite : Quantity
        getter prix : String
        getter unite : String = "C62"
      end

      class Avoir
        include Strict
        getter delai : Int32
        getter motif : String
        getter categorie : String
        getter lignes : Array(LigneVente)
      end

      class FactureFinale
        include Strict
        getter delai : Int32
        getter reglement : Reglement?
      end

      class Acceptation
        include Strict
        getter delai : Int32
        getter acompte : String?
        getter reglement_acompte : Reglement?
        getter facture_finale : FactureFinale?
      end

      class PaiementTva
        include Strict
        getter delai : Int32
        getter compte : String
        getter libelle : String
      end

      class LigneImage
        include Strict
        getter libelle : String
        getter montant : String
      end

      class ImageTicket
        include Strict
        getter modele : String = "ticket"
        getter enseigne : String
        getter adresse : String
        getter lignes : Array(LigneImage)
        getter tva : String
        getter paiement : String
        getter couleur : Array(Int32)
      end

      class Saisie
        include Strict
        getter si : Condition?
        getter libelle : String
        getter numero : String
        getter lignes : Array(LigneAchat)
        getter reglement : Reglement?
      end

      class CopieMicro
        include Strict
        getter enseigne : String
        getter adresse : String
        getter numero : String
        getter libelle : String
        getter taux : String
        getter couleur : Array(Int32)
      end

      class DeclarationTeledec
        include Strict
        getter nature : String
        getter exercice : String?
        getter annee : String?
        getter derniere_de : String?
      end

      class Pointage
        include Strict
        getter reference : String
        getter solde_debut : String?
        getter solde_fin : String?
      end

      class ElementPrevision
        include Strict
        getter libelle : String
        getter formule : String
        getter montant : String
      end

      class CategoriePrevision
        include Strict
        getter libelle : String
        getter elements : Array(ElementPrevision)
      end

      class AssurancePerso
        include Strict
        getter mode : String
        getter valeur : String
      end

      class LigneBudgetPerso
        include Strict
        getter categorie : String
        getter montant : String
        getter periode : String = "monthly"
      end

      class LigneTitrePerso
        include Strict
        getter titre : String
        getter quantite : String
        getter cours : String
      end

      # --- operations.yml : opérations -------------------------------------------

      abstract class Operation
        include YAML::Serializable
        include YAML::Serializable::Strict

        getter type : String
        getter date : String?
        getter si : Condition?
        getter ref : String?

        use_yaml_discriminator "type", {
          ecriture:                   Ecriture,
          banque:                     Banque,
          inventaire:                 Inventaire,
          mouvement_stock:            MouvementStock,
          achat:                      Achat,
          facture_plateforme:         FacturePlateforme,
          facture:                    Facture,
          bon_de_livraison:           BonDeLivraison,
          bon_de_retour:              BonDeRetour,
          devis:                      Devis,
          fin_de_mois:                FinDeMois,
          recapitulatives:            Recapitulatives,
          declaration_tva:            DeclarationTva,
          rapprochement:              Rapprochement,
          justificatif:               Justificatif,
          micro_recette:              MicroRecette,
          micro_achat:                MicroAchat,
          urssaf_mandat:              UrssafMandat,
          urssaf_declaration:         UrssafDeclaration,
          liberal_recette:            LiberalRecette,
          liberal_depense:            LiberalDepense,
          liberal_immobilisation:     LiberalImmobilisation,
          liberal_cloture:            LiberalCloture,
          rejet_reglement:            RejetReglement,
          relances:                   Relances,
          synchronisation_plateforme: SynchronisationPlateforme,
          teledeclarations:           Teledeclarations,
          crm:                        CrmOperation,
          modeles:                    ModelesOperation,
          import_releve:              ImportReleve,
          prevision:                  Prevision,
          perso_emprunt:              PersoEmprunt,
          perso_recurrente:           PersoRecurrente,
          perso_valorisation:         PersoValorisation,
          perso_budget:               PersoBudget,
          perso_deplacements:         PersoDeplacements,
          perso_operation:            PersoOperation,
        }
      end

      class Ecriture < Operation
        getter journal : String = "divers"
        getter libelle : String
        getter piece : String?
        getter lignes : Array(LigneEcriture)
      end

      class Banque < Operation
        getter journal : String = "banque"
        getter lignes : Array(LigneBanque)
      end

      class Inventaire < Operation
        getter libelle : String
        getter lignes : Array(LigneStock)
      end

      class MouvementStock < Operation
        getter libelle : String
        getter lignes : Array(LigneStock)
      end

      class Achat < Operation
        getter fournisseur : String
        getter numero : String
        getter libelle : String
        getter lignes : Array(LigneAchat)
        getter? copie : Bool = false
        getter? ventilation : Bool = false
        getter reglement : Reglement?
      end

      class FacturePlateforme < Operation
        getter fournisseur : String
        getter numero : String
        getter libelle : String
        getter note : String = ""
        getter taux : String
        getter lignes : Array(LignePlateforme)
        getter comptabiliser : Condition?
        getter reglement : Reglement?
      end

      class Facture < Operation
        getter client : String
        getter objet : String?
        getter categorie : String
        getter reference_commande : String?
        getter? chorus_pro : Bool = false
        getter lignes : Array(LigneVente)
        getter avoir : Avoir?
        getter reglement : Reglement?
      end

      class BonDeLivraison < Operation
        getter client : String
        getter notes : String = ""
        getter categorie : String
        getter lignes : Array(LigneVente)
      end

      class BonDeRetour < Operation
        getter bon : String
        getter motif : String
        getter notes : String = ""
        getter categorie : String
        getter lignes : Array(LigneVente)
      end

      class Devis < Operation
        getter client : String
        getter objet : String = ""
        getter categorie : String
        getter lignes : Array(LigneVente)
        getter acceptation : Acceptation?
        getter refus : Delai?
      end

      class FinDeMois < Operation
      end

      class Recapitulatives < Operation
        getter reglement : Reglement?
      end

      class DeclarationTva < Operation
        getter formulaire : String
        getter periodicite : String = "month"
        getter periode : String
        getter journal : String = "divers"
        getter paiement : PaiementTva?
      end

      class Rapprochement < Operation
        getter journal : String = "banque"
        getter mois : String
      end

      class Justificatif < Operation
        getter fichier : String
        getter source : String = "photo"
        getter genre : String = "ticket"
        getter fournisseur : String?
        getter nom_fournisseur : String
        getter montant : String
        getter reference : String?
        getter image : ImageTicket
        getter saisie : Saisie?
      end

      class MicroRecette < Operation
        getter nature : String
        getter montant : String
        getter moyen : String
        getter tiers : String = ""
        getter libelle : String
      end

      class MicroAchat < Operation
        getter nature : String
        getter montant : String
        getter moyen : String
        getter fournisseur : String?
        getter tiers : String = ""
        getter libelle : String
        getter reference : String?
        getter copie : CopieMicro?
      end

      class UrssafMandat < Operation
        getter iban : String
        getter bic : String
        getter titulaire : String
      end

      class UrssafDeclaration < Operation
        getter periode : String
        getter? paiement : Bool = true
      end

      class LiberalRecette < Operation
        getter montant : String
        getter libelle : String
        getter moyen : String = "transfer"
        getter tiers : String = ""
      end

      class LiberalDepense < Operation
        getter rubrique : String
        getter montant : String
        getter libelle : String
        getter tiers : String = ""
        getter part_privee : String = "0"
        getter moyen : String = "transfer"
      end

      class LiberalImmobilisation < Operation
        getter libelle : String
        getter categorie : String
        getter montant : String
        getter duree : Int32
        getter moyen : String = "transfer"
        getter tiers : String = ""
      end

      class LiberalCloture < Operation
        getter exercice : String
      end

      class RejetReglement < Operation
        getter clients : Array(String)
        getter motif : String
        getter texte : String = ""
        getter frais : String = "0"
        getter? refacturer : Bool = false
        getter taux_frais : String?
      end

      class Relances < Operation
        getter envoyer : Int32 = 0
      end

      class SynchronisationPlateforme < Operation
      end

      class Teledeclarations < Operation
        getter declarations : Array(DeclarationTeledec)
      end

      class CrmOperation < Operation
        getter fichier : String
      end

      class ModelesOperation < Operation
        getter langue : String = "fr"
        getter defaut : String?
        getter? rendre_derniere_facture : Bool = false
      end

      class ImportReleve < Operation
        getter journal : String = "banque"
        getter fichier : String
        getter format : String?
        getter? transferer : Bool = true
        getter pointage : Pointage?
      end

      class Prevision < Operation
        getter nom : String
        getter debut : String
        getter fin : String
        getter categories : Array(CategoriePrevision)
      end

      # Emprunt d'un compte de dette du foyer et son tableau d'amortissement.
      class PersoEmprunt < Operation
        getter compte : String
        getter compte_payeur : String
        getter capital : String
        getter taux : String
        getter echeances : Int32
        getter premiere_echeance : String
        getter differe : Int32 = 0
        getter type_differe : String = "none"
        getter assurance : AssurancePerso?
        getter categorie_interets : String
        getter categorie_assurance : String?
      end

      # Opération récurrente de l'échéancier, à partir de la date de
      # l'opération (ou de `premiere`).
      class PersoRecurrente < Operation
        getter compte : String
        getter sens : String = "expense"
        getter beneficiaire : String
        getter montant : String
        getter? estime : Bool = false
        getter frequence : String = "monthly"
        getter intervalle : Int32?
        getter premiere : String?
        getter derniere : String?
        getter? jour_ouvre : Bool = false
        getter categorie : String?
        getter vers : String?
        getter membre : String?
      end

      # Valeur d'un placement ou d'un bien à la date de l'opération.
      class PersoValorisation < Operation
        getter compte : String
        getter valeur : String?
        getter lignes : Array(LigneTitrePerso) = [] of LigneTitrePerso
        getter note : String = ""
      end

      # Budget d'une année : montant par catégorie (compte du plan).
      class PersoBudget < Operation
        getter annee : String
        getter lignes : Array(LigneBudgetPerso)
      end

      # Déplacements professionnels d'une année (frais réels).
      class PersoDeplacements < Operation
        getter annee : String
        getter puissance : Int32
        getter kilometres : Int32
        getter libelle : String = ""
        getter membre : String?
      end

      # Opération saisie en recettes et dépenses (catégorie : compte du plan ;
      # virement : `vers`, libellé d'un compte du foyer).
      class PersoOperation < Operation
        getter compte : String
        getter sens : String = "expense"
        getter montant : String
        getter categorie : String?
        getter vers : String?
        getter beneficiaire : String = ""
        getter membre : String?
        getter note : String = ""
      end

      class OperationsFile
        include Strict
        getter format : Int32
        getter operations : Array(Operation) = [] of Operation
        getter recentes : Array(Operation) = [] of Operation
        getter fin : Array(Operation) = [] of Operation
      end

      # --- crm.yml -----------------------------------------------------------------

      class Organisation
        include Strict
        getter ref : String
        getter nom : String
        getter nature : String
        getter siren : String = ""
        getter ville : String = ""
        getter pays : String = "FR"
        getter origine : String
        getter responsable : String?
      end

      class Contact
        include Strict
        getter ref : String
        getter organisation : String?
        getter civilite : String?
        getter prenom : String = ""
        getter nom : String
        getter fonction : String?
        getter courriel : String?
        getter base_legale : String = "legitimate_interest"
        getter origine : String?
        getter opposition : String?
      end

      class Perte
        include Strict
        getter motif : String
        getter commentaire : String = ""
      end

      class Opportunite
        include Strict
        getter ref : String?
        getter titre : String
        getter organisation : String
        getter contact : String?
        getter montant : String
        getter etape : String
        getter responsable : String?
        getter cloture_prevue : String
        getter origine : String?
        getter perte : Perte?
        getter? devis : Bool = false
      end

      class Activite
        include Strict
        getter genre : String
        getter objet : String
        getter echeance : String
        getter responsable : String?
        getter opportunite : String?
        getter organisation : String?
      end

      class CrmFile
        include Strict
        getter format : Int32
        getter organisations : Array(Organisation) = [] of Organisation
        getter contacts : Array(Contact) = [] of Contact
        getter opportunites : Array(Opportunite) = [] of Opportunite
        getter activites : Array(Activite) = [] of Activite
      end

      # --- attendus.yml ------------------------------------------------------------

      class Controle
        include Strict
        getter type : String
        getter exercice : String?
        getter prefixe : String?
        getter sens : String?
        getter journaux : String?
        getter montant : String?
        getter formulaire : String?
        getter nombre : Int32?
        getter statut : String?
        getter minimum : Int32?
        getter natures : Array(String)?
        getter frais : String?
        getter recettes : String?
        getter achats : String?
        getter depenses : String?
        getter payees : Bool?
        getter etat : String?
        getter comptabilisees : Bool?
      end

      class Attendus
        include Strict
        getter format : Int32
        getter controles : Array(Controle)
      end
    end
  end
end
