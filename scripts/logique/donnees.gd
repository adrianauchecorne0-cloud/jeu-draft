class_name Donnees
extends RefCounted
## Toutes les valeurs du jeu, lues dans les fichiers du dossier data/.
## Aucune stat ne doit être écrite en dur dans le code : tout passe par ici.
## Logique pure : aucun nœud, aucun affichage.

const DOSSIER := "res://data/"
const CHAMPS_TROUPE := ["nom", "forme", "cout", "unites_par_carte", "vie", "degats", "portee", "vitesse"]
const CHAMPS_STRUCTURE := ["nom", "cout", "max_par_joueur"]

## Stats de chaque troupe, rangées par identifiant ("guerrier", "archer", "colosse").
var troupes: Dictionary = {}
## Stats de chaque structure, rangées par identifiant ("mur").
var structures: Dictionary = {}
## Règles générales : sections "terrain", "combat", "manches".
var regles: Dictionary = {}


## Charge les trois fichiers de données. Renvoie null si l'un d'eux est illisible.
static func charger(dossier: String = DOSSIER) -> Donnees:
	var d := Donnees.new()
	d.troupes = _sans_commentaires(_lire_json(dossier + "troupes.json"))
	d.structures = _sans_commentaires(_lire_json(dossier + "structures.json"))
	d.regles = _sans_commentaires(_lire_json(dossier + "regles.json"))
	if d.troupes.is_empty() or d.structures.is_empty() or d.regles.is_empty():
		return null
	return d


## Lit un nombre entier dans les règles, par exemple regle_entiere("terrain", "colonnes").
func regle_entiere(section: String, cle: String) -> int:
	var bloc: Dictionary = regles.get(section, {})
	if not bloc.has(cle):
		push_error("Règle manquante dans regles.json : %s / %s" % [section, cle])
		return 0
	return int(bloc[cle])


## Liste des champs manquants dans les fichiers (vide si tout va bien).
func problemes() -> Array[String]:
	var liste: Array[String] = []
	for cle in troupes:
		for champ in CHAMPS_TROUPE:
			if not troupes[cle].has(champ):
				liste.append("troupes.json : il manque %s pour %s" % [champ, cle])
	for cle in structures:
		for champ in CHAMPS_STRUCTURE:
			if not structures[cle].has(champ):
				liste.append("structures.json : il manque %s pour %s" % [champ, cle])
	return liste


static func _lire_json(chemin: String) -> Dictionary:
	var fichier := FileAccess.open(chemin, FileAccess.READ)
	if fichier == null:
		push_error("Impossible d'ouvrir le fichier %s" % chemin)
		return {}
	var contenu: Variant = JSON.parse_string(fichier.get_as_text())
	if typeof(contenu) != TYPE_DICTIONARY:
		push_error("%s n'est pas un JSON valide (virgule en trop ou manquante ?)" % chemin)
		return {}
	return contenu


## Retire les clés qui commencent par « _ » : ce sont des commentaires pour Adrian.
static func _sans_commentaires(dico: Dictionary) -> Dictionary:
	var propre := {}
	for cle in dico:
		if not str(cle).begins_with("_"):
			propre[cle] = dico[cle]
	return propre
