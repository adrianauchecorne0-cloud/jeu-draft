class_name Combat
extends RefCounted
## Le combat automatique, tour par tour. Logique pure : aucun nœud, aucun affichage.
## On peut le lancer des milliers de fois sans écran (équilibrage, compositions enregistrées).
##
## Une « armée » est un Dictionary :
##   {"groupes": [{"type": "soldat", "cases": [Vector2i(colonne, rang), ...]}, ...],
##    "murs": [Vector2i(colonne, rang), ...]}
## Les cases sont vues par le joueur (voir Terrain) : la même armée peut donc jouer
## en bleu (en bas de l'écran) ou en rouge (en haut, tournée de 180°).
## Un mur posé en (colonne, rang) couvre un carré de « taille » cases (structures.json)
## qui s'étend vers la droite et vers le fond du camp.

const BLEU := 0
const ROUGE := 1
const NUL := -1
const EPSILON := 0.0001
## Nombre maximum de cases explorées quand une unité cherche à contourner des troupes.
const RECHERCHE_MAX := 600

var donnees: Donnees
var terrain: Terrain
var colonnes: int
var lignes: int
var lignes_par_camp: int
var tours_max: int
## Si false, on ne garde pas l'historique (plus rapide pour les simulations en masse).
var enregistrer: bool

## Unités encore vivantes.
var unites: Array[Unite] = []
## Toutes les unités du combat, mortes comprises (pour l'affichage).
var toutes_les_unites: Array[Unite] = []
## Cases couvertes par des murs : case réelle (Vector2i) -> camp propriétaire.
var murs: Dictionary = {}
## Un élément par mur posé : {"camp": int, "cases": Array[Vector2i]} (pour l'affichage).
var blocs_murs: Array = []
## Qui est où : case réelle (Vector2i) -> Unite.
var occupation: Dictionary = {}
## Numéro du dernier tour joué (0 avant le premier tour).
var tour: int = 0
## Un élément par tour joué : la liste des événements de ce tour, dans l'ordre :
##   {"type": "attaque", "source": id, "cible": id, "degats": int, "vie_apres": int}
##   {"type": "mort", "unite": id}
##   {"type": "deplacement", "unite": id, "de": Vector2i, "vers": Vector2i}
var historique: Array = []
## Vide tant que le combat n'est pas fini. Ensuite :
##   {"gagnant": BLEU, ROUGE ou NUL, "raison": "elimination" ou "limite_de_tours",
##    "tours": int, "vie_restante": [bleu, rouge], "unites_restantes": [bleu, rouge]}
var resultat: Dictionary = {}

var _par_id: Dictionary = {}
var _prochain_id: int = 1
## Ordre de préférence des directions, vu par chaque camp : avancer, gauche, droite, reculer.
var _directions: Array = []
## Cache : portée -> liste des décalages (dx, dy) à portée.
var _disques: Dictionary = {}
## Champs de distances du tour en cours : (camp, portée) -> distance de chaque case
## à la position d'attaque la plus proche (-1 = inaccessible).
var _champs: Dictionary = {}
## 1 si la case (indice y * colonnes + x) est un mur.
var _est_mur := PackedByteArray()


## limiter_murs = false : murs illimités (bac à sable).
func _init(p_donnees: Donnees, armee_bleue: Dictionary, armee_rouge: Dictionary,
		p_enregistrer: bool = true, limiter_murs: bool = true) -> void:
	donnees = p_donnees
	enregistrer = p_enregistrer
	terrain = Terrain.new(donnees)
	colonnes = terrain.colonnes
	lignes = terrain.lignes
	lignes_par_camp = terrain.lignes_par_camp
	tours_max = donnees.regle_entiere("combat", "tours_max")
	_directions = [
		_ordre_directions(Vector2i(0, -1), Vector2i(-1, 0)),
		_ordre_directions(Vector2i(0, 1), Vector2i(1, 0)),
	]
	_placer_unites(armee_bleue, BLEU)
	_placer_unites(armee_rouge, ROUGE)
	_placer_murs(armee_bleue, BLEU, limiter_murs)
	_placer_murs(armee_rouge, ROUGE, limiter_murs)
	_est_mur.resize(colonnes * lignes)
	for c in murs:
		_est_mur[_indice(c)] = 1
	_verifier_fin()


# --- Utilisation -------------------------------------------------------------

## Joue le combat jusqu'au bout et renvoie le résultat.
func simuler() -> Dictionary:
	while resultat.is_empty():
		jouer_tour()
	return resultat


## Joue un seul tour (pour l'affichage pas à pas).
func jouer_tour() -> void:
	if not resultat.is_empty():
		return
	tour += 1
	var evenements: Array = []
	var occupees := _phase_attaques(evenements)
	_phase_deplacements(occupees, evenements)
	if enregistrer:
		historique.append(evenements)
	_verifier_fin()


func unite_par_id(id: int) -> Unite:
	return _par_id.get(id)


## Case vue par un camp -> case réelle (voir Terrain).
func vers_grille(camp: int, case_camp: Vector2i) -> Vector2i:
	return terrain.vers_grille(camp, case_camp)


## Cette case réelle fait-elle partie de la zone de placement de ce camp ?
func dans_zone(camp: int, c: Vector2i) -> bool:
	return terrain.dans_zone(camp, c)


# --- Phase 1 : attaques --------------------------------------------------------

## Chaque unité qui a un ennemi à portée le frappe, si elle est rechargée.
## Tout le monde frappe en même temps (dégâts appliqués à la fin), donc deux unités
## peuvent s'entretuer. Renvoie les unités qui ont un ennemi à portée : elles ne
## bougent pas ce tour-ci (même si elles rechargent).
func _phase_attaques(evenements: Array) -> Dictionary:
	var occupees := {}
	var degats_recus := {}
	var vie_projetee := {}
	for u in unites:
		if u.recharge > 0:
			u.recharge -= 1
		var cible := _choisir_cible(u)
		if cible == null:
			continue
		occupees[u] = true
		if u.recharge > 0:
			continue
		u.recharge = u.cadence
		degats_recus[cible] = int(degats_recus.get(cible, 0)) + u.degats
		if enregistrer:
			var vie_avant: int = vie_projetee.get(cible, cible.vie)
			vie_projetee[cible] = maxi(0, vie_avant - u.degats)
			evenements.append({"type": "attaque", "source": u.id, "cible": cible.id,
				"degats": u.degats, "vie_apres": vie_projetee[cible]})
	for touchee in degats_recus:
		touchee.vie = maxi(0, touchee.vie - int(degats_recus[touchee]))
	var survivantes: Array[Unite] = []
	for u in unites:
		if u.est_vivante():
			survivantes.append(u)
		else:
			occupation.erase(u.cellule)
			if enregistrer:
				evenements.append({"type": "mort", "unite": u.id})
	unites = survivantes
	return occupees


## La cible : l'ennemi à portée le plus proche ; à égalité, le moins de vie ;
## puis le plus petit numéro.
func _choisir_cible(u: Unite) -> Unite:
	var meilleure: Unite = null
	var meilleure_distance := 0
	for e in unites:
		if e.camp == u.camp:
			continue
		var d := _distance_carre(u.cellule, e.cellule)
		if d > u.portee_carre:
			continue
		if meilleure == null or _est_prioritaire(e, d, meilleure, meilleure_distance):
			meilleure = e
			meilleure_distance = d
	return meilleure


func _est_prioritaire(e: Unite, d: int, actuelle: Unite, d_actuelle: int) -> bool:
	if d != d_actuelle:
		return d < d_actuelle
	if e.vie != actuelle.vie:
		return e.vie < actuelle.vie
	return e.id < actuelle.id


# --- Phase 2 : déplacements ----------------------------------------------------

## Les unités sans ennemi à portée bougent une par une, en alternant bleu et rouge.
func _phase_deplacements(occupees: Dictionary, evenements: Array) -> void:
	_champs.clear()
	for u in _ordre_de_deplacement():
		if not occupees.has(u):
			_deplacer(u, evenements)


## Alternance bleu / rouge ; le camp qui commence change à chaque tour (équité).
func _ordre_de_deplacement() -> Array[Unite]:
	var par_camp: Array = [[], []]
	for u in unites:
		par_camp[u.camp].append(u)
	par_camp[BLEU].sort_custom(_passe_avant)
	par_camp[ROUGE].sort_custom(_passe_avant)
	var premier := BLEU if tour % 2 == 1 else ROUGE
	var second := 1 - premier
	var ordre: Array[Unite] = []
	var i := 0
	while i < par_camp[premier].size() or i < par_camp[second].size():
		if i < par_camp[premier].size():
			ordre.append(par_camp[premier][i])
		if i < par_camp[second].size():
			ordre.append(par_camp[second][i])
		i += 1
	return ordre


## Dans un camp : la plus avancée d'abord, puis de gauche à droite (vu par ce camp).
func _passe_avant(a: Unite, b: Unite) -> bool:
	var avance_a := _avancement(a)
	var avance_b := _avancement(b)
	if avance_a != avance_b:
		return avance_a > avance_b
	var gauche_a := _gauche(a)
	var gauche_b := _gauche(b)
	if gauche_a != gauche_b:
		return gauche_a < gauche_b
	return a.id < b.id


func _avancement(u: Unite) -> int:
	return -u.cellule.y if u.camp == BLEU else u.cellule.y


func _gauche(u: Unite) -> int:
	return u.cellule.x if u.camp == BLEU else -u.cellule.x


func _deplacer(u: Unite, evenements: Array) -> void:
	# La réserve se remplit de « vitesse » à chaque tour. On la plafonne pour
	# qu'une unité bloquée ne fasse pas ensuite un grand bond.
	u.reserve_mouvement = minf(u.reserve_mouvement + u.vitesse, maxf(1.0, u.vitesse))
	while u.reserve_mouvement >= 1.0 - EPSILON:
		if _a_un_ennemi_a_portee(u):
			return
		var pas := _prochain_pas(u)
		if pas == u.cellule:
			return
		u.reserve_mouvement -= 1.0
		var depart := u.cellule
		occupation.erase(depart)
		u.cellule = pas
		occupation[pas] = u
		if enregistrer:
			evenements.append({"type": "deplacement", "unite": u.id, "de": depart, "vers": pas})


func _a_un_ennemi_a_portee(u: Unite) -> bool:
	for e in unites:
		if e.camp != u.camp and u.a_portee_de(e.cellule):
			return true
	return false


## Prochaine case vers la position d'attaque la plus proche.
## 1. On suit le champ de distances (qui contourne les murs) vers une case libre.
## 2. Si des troupes bloquent, on cherche un chemin qui les contourne.
## 3. Sinon, on attend.
func _prochain_pas(u: Unite) -> Vector2i:
	var champ := _champ(u.camp, u.portee)
	var distance := champ[_indice(u.cellule)]
	if distance > 0:
		for direction in _directions[u.camp]:
			var voisine: Vector2i = u.cellule + direction
			if _est_libre(voisine) and champ[_indice(voisine)] == distance - 1:
				return voisine
	if distance < 0:
		return u.cellule
	return _contourner(u, champ)


## Champ de distances pour un camp et une portée, calculé une fois par tour.
func _champ(camp: int, portee: int) -> PackedInt32Array:
	var cle := camp * 100000 + portee
	if not _champs.has(cle):
		_champs[cle] = _calculer_champ(camp, portee)
	return _champs[cle]


## Recherche en largeur à partir de toutes les cases d'où l'on peut frapper
## un ennemi. Les murs bloquent, les troupes non (elles bougent).
func _calculer_champ(camp: int, portee: int) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(colonnes * lignes)
	distances.fill(-1)
	var file: Array[Vector2i] = []
	var disque := _disque(portee)
	for e in unites:
		if e.camp == camp:
			continue
		for decalage in disque:
			var c: Vector2i = e.cellule + decalage
			if not terrain.dans_grille(c):
				continue
			var i := _indice(c)
			if _est_mur[i] == 0 and distances[i] == -1:
				distances[i] = 0
				file.append(c)
	var k := 0
	while k < file.size():
		var c := file[k]
		k += 1
		var suivante := distances[_indice(c)] + 1
		for direction in _directions[BLEU]:
			var v: Vector2i = c + direction
			if not terrain.dans_grille(v):
				continue
			var i := _indice(v)
			if _est_mur[i] == 0 and distances[i] == -1:
				distances[i] = suivante
				file.append(v)
	return distances


## Recherche en largeur depuis l'unité, en contournant murs ET troupes, vers la
## case libre la plus proche d'où elle peut frapper. Renvoie le premier pas.
func _contourner(u: Unite, champ: PackedInt32Array) -> Vector2i:
	var depart := u.cellule
	var parents := {depart: depart}
	var file: Array[Vector2i] = [depart]
	var directions: Array[Vector2i] = _directions[u.camp]
	var i := 0
	while i < file.size() and i < RECHERCHE_MAX:
		var c := file[i]
		i += 1
		if c != depart and champ[_indice(c)] == 0:
			return _premier_pas(parents, c, depart)
		for d in directions:
			var voisine := c + d
			if parents.has(voisine) or not _est_libre(voisine):
				continue
			parents[voisine] = c
			file.append(voisine)
	return depart


func _premier_pas(parents: Dictionary, arrivee: Vector2i, depart: Vector2i) -> Vector2i:
	var courant := arrivee
	while parents[courant] != depart:
		courant = parents[courant]
	return courant


func _est_libre(c: Vector2i) -> bool:
	return terrain.dans_grille(c) and _est_mur[_indice(c)] == 0 and not occupation.has(c)


func _disque(portee: int) -> Array[Vector2i]:
	if not _disques.has(portee):
		var limite := (portee + 0.5) * (portee + 0.5)
		var decalages: Array[Vector2i] = []
		for dy in range(-portee, portee + 1):
			for dx in range(-portee, portee + 1):
				if (dx != 0 or dy != 0) and dx * dx + dy * dy <= limite:
					decalages.append(Vector2i(dx, dy))
		_disques[portee] = decalages
	return _disques[portee]


# --- Fin du combat -------------------------------------------------------------

func _verifier_fin() -> void:
	var nombre := [0, 0]
	var vie := [0, 0]
	for u in unites:
		nombre[u.camp] += 1
		vie[u.camp] += u.vie
	var gagnant := NUL
	var raison := ""
	if nombre[BLEU] == 0 or nombre[ROUGE] == 0:
		raison = "elimination"
		if nombre[BLEU] > 0:
			gagnant = BLEU
		elif nombre[ROUGE] > 0:
			gagnant = ROUGE
	elif tour >= tours_max:
		raison = "limite_de_tours"
		if vie[BLEU] > vie[ROUGE]:
			gagnant = BLEU
		elif vie[ROUGE] > vie[BLEU]:
			gagnant = ROUGE
	else:
		return
	resultat = {"gagnant": gagnant, "raison": raison, "tours": tour,
		"vie_restante": vie, "unites_restantes": nombre}


# --- Placement -----------------------------------------------------------------

func _placer_unites(armee: Dictionary, camp: int) -> void:
	for groupe in armee.get("groupes", []):
		var type_troupe := str(groupe.get("type", ""))
		if not donnees.troupes.has(type_troupe):
			push_error("Troupe inconnue : %s (vérifie data/troupes.json)" % type_troupe)
			continue
		var stats: Dictionary = donnees.troupes[type_troupe]
		for case_camp in groupe.get("cases", []):
			var c := vers_grille(camp, _en_case(case_camp))
			if not _case_libre_dans_zone(camp, c):
				push_warning("Case %s refusée pour %s (hors zone ou déjà prise)" % [str(case_camp), type_troupe])
				continue
			var u := Unite.new(_prochain_id, camp, type_troupe, stats, c)
			_prochain_id += 1
			unites.append(u)
			toutes_les_unites.append(u)
			occupation[c] = u
			_par_id[u.id] = u


func _placer_murs(armee: Dictionary, camp: int, limiter_murs: bool) -> void:
	var mur: Dictionary = donnees.structures.get("mur", {})
	var max_murs := int(mur.get("max_par_joueur", 0))
	var taille := maxi(1, int(mur.get("taille", 1)))
	var nombre_murs := 0
	for case_camp in armee.get("murs", []):
		var cases := terrain.cases_mur(camp, _en_case(case_camp), taille)
		var possible := not limiter_murs or nombre_murs < max_murs
		for c in cases:
			if not _case_libre_dans_zone(camp, c):
				possible = false
		if not possible:
			push_warning("Mur refusé en %s (hors zone, case prise ou trop de murs)" % str(case_camp))
			continue
		for c in cases:
			murs[c] = camp
		blocs_murs.append({"camp": camp, "cases": cases})
		nombre_murs += 1


func _case_libre_dans_zone(camp: int, c: Vector2i) -> bool:
	return dans_zone(camp, c) and not occupation.has(c) and not murs.has(c)


## Accepte Vector2i(colonne, rang) ou [colonne, rang] (format JSON).
static func _en_case(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	push_error("Case invalide : %s" % str(v))
	return Vector2i(-100, -100)


# --- Outils --------------------------------------------------------------------

func _indice(c: Vector2i) -> int:
	return c.y * colonnes + c.x


func _ordre_directions(avant: Vector2i, gauche: Vector2i) -> Array[Vector2i]:
	var ordre: Array[Vector2i] = [avant, gauche, -gauche, -avant]
	return ordre


static func _distance_carre(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy
