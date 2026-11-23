class_name VueTerrain
extends Control
## Dessine le terrain (sans grille visible), les murs et les unités, et rend le
## combat vivant : petit balancement (wiggle), rebond quand elles marchent, élan
## au corps à corps, flèches, éclairs de coup, chiffres de dégâts, disparition.
## Ne décide rien : recopie l'état du Combat, puis rejoue les événements de chaque tour.

## Touché ou glissé sur le terrain (mode placement). debut = premier contact.
signal case_touchee(cellule: Vector2i, debut: bool)

const COULEURS_CAMP := [Color("4d8dff"), Color("ff5a5a")]
const COULEURS_ZONE := [Color(0.11, 0.16, 0.28), Color(0.28, 0.11, 0.14)]
const COULEUR_NEUTRE := Color(0.15, 0.15, 0.18)
const COULEUR_MUR := Color("e2a84b")
const FORMES_PAR_DEFAUT := {"cercle": "cercle", "carre": "carre", "triangle": "triangle"}

## Durée d'un tour de combat à l'écran (règle « affichage » de regles.json).
var secondes_par_tour := 0.1
## Message affiché par-dessus le terrain (vide = rien).
var texte_fin := ""
## En mode placement : on peut toucher le terrain, et la zone bleue est mise en valeur.
var mode_placement := false
## Ce qu'on s'apprête à poser (type de troupe ou "mur"), pour l'aperçu sous la souris.
var type_apercu := ""

var _colonnes := 27
var _lignes := 42
var _lignes_par_camp := 18
var _taille_mur := 2
## Une entrée par unité (id) : tout ce qu'il faut pour la dessiner et l'animer.
var _unites: Dictionary = {}
var _blocs_murs: Array = []
## Effets en cours : flèches, coups, chiffres, disparitions.
var _effets: Array = []
var _temps := 0.0
var _police: Font
var _troupes: Dictionary = {}
var _images: Dictionary = {}
var _image_mur: Texture2D
var _survol := Vector2i(-1, -1)
var _derniere_case := Vector2i(-1, -1)
var _nombre_chiffres := 0


func _ready() -> void:
	_police = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP


## Recopie l'état de départ d'un combat (avant son premier tour).
func preparer(combat: Combat) -> void:
	_colonnes = combat.colonnes
	_lignes = combat.lignes
	_lignes_par_camp = combat.lignes_par_camp
	_troupes = combat.donnees.troupes
	var mur: Dictionary = combat.donnees.structures.get("mur", {})
	_taille_mur = maxi(1, int(mur.get("taille", 1)))
	_image_mur = _charger_image(str(mur.get("image", "")))
	_blocs_murs = combat.blocs_murs.duplicate()
	_effets.clear()
	_unites.clear()
	for u in combat.toutes_les_unites:
		_unites[u.id] = {
			"camp": u.camp,
			"type": u.type_troupe,
			"forme": u.forme,
			"portee": u.portee,
			"vie_max": u.vie_max,
			"vie": u.vie,
			"pos": Vector2(u.cellule),
			"cible": Vector2(u.cellule),
			# Un peu plus vite que la logique, pour rattraper sans saccades.
			"vitesse": maxf(u.vitesse, 0.3) / secondes_par_tour * 1.25,
			"phase": float(u.id) * 1.7,
			"eclair": -1.0,
			"elan": -1.0,
			"elan_vers": Vector2.ZERO,
			"disparait": -1.0,
		}
	texte_fin = ""
	queue_redraw()


## Rejoue les événements d'un tour de Combat (Combat.historique).
func appliquer_tour(evenements: Array) -> void:
	# Dégâts reçus pendant ce tour, regroupés par cible : un seul chiffre par unité.
	var coups := {}
	for ev in evenements:
		match ev["type"]:
			"attaque":
				var source: Dictionary = _unites[ev["source"]]
				var cible: Dictionary = _unites[ev["cible"]]
				var delai := 0.07
				if int(source["portee"]) > 1:
					var depart: Vector2 = source["pos"]
					var distance := depart.distance_to(cible["pos"])
					delai = clampf(distance * 0.022, 0.1, 0.35)
					_effets.append({"type": "fleche", "de": source["pos"], "vers": cible["pos"],
						"camp": source["camp"], "age": 0.0, "delai": 0.0, "duree": delai})
				else:
					source["elan"] = 0.0
					source["elan_vers"] = cible["pos"]
					_effets.append({"type": "coup", "pos": cible["pos"], "de": source["pos"],
						"age": 0.0, "delai": delai, "duree": 0.16})
				var total: Dictionary = coups.get(ev["cible"], {"degats": 0, "delai": 0.0})
				total["degats"] += ev["degats"]
				total["delai"] = maxf(total["delai"], delai)
				total["vie"] = ev["vie_apres"]
				coups[ev["cible"]] = total
			"mort":
				var coup: Dictionary = coups.get(ev["unite"], {})
				_unites[ev["unite"]]["disparait"] = -float(coup.get("delai", 0.0))
			"deplacement":
				_unites[ev["unite"]]["cible"] = Vector2(ev["vers"])
	for id in coups:
		var coup: Dictionary = coups[id]
		_nombre_chiffres += 1
		_effets.append({"type": "degats", "id": id, "texte": "-%d" % coup["degats"], "vie": coup["vie"],
			"pos": _unites[id]["pos"], "decalage": float(_nombre_chiffres % 3 - 1),
			"age": 0.0, "delai": coup["delai"], "duree": 0.55})


## Minuteries des unités : -1 = rien en cours.
## « eclair » : flash blanc quand l'unité est touchée (0,15 s).
## « elan » : coup de corps à corps vers la cible (0,16 s).
## « disparait » : disparition après la mort (0,4 s) ; négatif = petit délai avant.
func _process(delta: float) -> void:
	_temps += delta
	for id in _unites.keys():
		var e: Dictionary = _unites[id]
		var pos: Vector2 = e["pos"]
		var cible: Vector2 = e["cible"]
		var vitesse: float = e["vitesse"]
		if pos.distance_to(cible) > 2.5:
			vitesse *= 3.0
		e["pos"] = pos.move_toward(cible, vitesse * delta)
		if e["eclair"] >= 0.0:
			e["eclair"] = e["eclair"] + delta if e["eclair"] + delta < 0.15 else -1.0
		if e["elan"] >= 0.0:
			e["elan"] = e["elan"] + delta if e["elan"] + delta < 0.16 else -1.0
		if e["disparait"] > -0.9:
			e["disparait"] += delta
			if e["disparait"] > 0.4:
				_unites.erase(id)
	var restants: Array = []
	for effet in _effets:
		effet["age"] += delta
		if effet["type"] == "degats" and effet["age"] >= effet["delai"] and not effet.has("fait"):
			effet["fait"] = true
			if _unites.has(effet["id"]):
				_unites[effet["id"]]["vie"] = effet["vie"]
				_unites[effet["id"]]["eclair"] = 0.0
		if effet["age"] < effet["delai"] + effet["duree"]:
			restants.append(effet)
	_effets = restants
	queue_redraw()


# --- Toucher le terrain (placement) --------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var bouton := event as InputEventMouseButton
		if bouton.button_index == MOUSE_BUTTON_LEFT and bouton.pressed and mode_placement:
			var c := case_sous(bouton.position)
			if c.x >= 0:
				_derniere_case = c
				case_touchee.emit(c, true)
	elif event is InputEventMouseMotion:
		var mouvement := event as InputEventMouseMotion
		var c := case_sous(mouvement.position)
		_survol = c
		if mode_placement and (mouvement.button_mask & MOUSE_BUTTON_MASK_LEFT) and c.x >= 0 and c != _derniere_case:
			_derniere_case = c
			case_touchee.emit(c, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_survol = Vector2i(-1, -1)


## Case réelle sous un point de l'écran (en pixels, dans ce contrôle), ou (-1, -1).
func case_sous(point: Vector2) -> Vector2i:
	var t := _taille_case()
	if t <= 0.0:
		return Vector2i(-1, -1)
	var g := ((point - _origine()) / t).floor()
	var c := Vector2i(int(g.x), int(g.y))
	if c.x < 0 or c.y < 0 or c.x >= _colonnes or c.y >= _lignes:
		return Vector2i(-1, -1)
	return c


# --- Dessin ------------------------------------------------------------------

func _draw() -> void:
	var t := _taille_case()
	if t <= 0.0:
		return
	_dessiner_terrain(t)
	for bloc in _blocs_murs:
		_dessiner_mur(bloc["cases"], t, 1.0)
	# Les unités du haut d'abord, pour que celles du bas passent devant.
	var ids := _unites.keys()
	ids.sort_custom(func(a, b): return _unites[a]["pos"].y < _unites[b]["pos"].y)
	for id in ids:
		_dessiner_unite(_unites[id], t)
	for effet in _effets:
		if effet["age"] >= effet["delai"]:
			_dessiner_effet(effet, t)
	if mode_placement:
		_dessiner_apercu(t)
	if texte_fin != "":
		_dessiner_fin()


func _dessiner_terrain(t: float) -> void:
	var o := _origine()
	var haut_rouge := Rect2(o, Vector2(_colonnes, _lignes_par_camp) * t)
	var milieu := Rect2(o + Vector2(0, _lignes_par_camp * t), Vector2(_colonnes, _lignes - 2 * _lignes_par_camp) * t)
	var bas_bleu := Rect2(o + Vector2(0, (_lignes - _lignes_par_camp) * t), Vector2(_colonnes, _lignes_par_camp) * t)
	draw_rect(haut_rouge, COULEURS_ZONE[1])
	draw_rect(milieu, COULEUR_NEUTRE)
	draw_rect(bas_bleu, COULEURS_ZONE[0])
	if mode_placement:
		var pulsation := 0.35 + 0.25 * sin(_temps * 3.0)
		draw_rect(bas_bleu.grow(-2.0), Color(COULEURS_CAMP[0], pulsation), false, 3.0)


func _dessiner_unite(e: Dictionary, t: float) -> void:
	var pos: Vector2 = e["pos"]
	var bouge := pos.distance_to(e["cible"]) > 0.02
	var phase: float = e["phase"]
	var disparition := clampf(e["disparait"] / 0.4, 0.0, 1.0) if e["disparait"] >= 0.0 else 0.0
	var alpha := 1.0 - disparition
	# Wiggle : balancement gauche-droite, plus fort quand l'unité marche.
	var angle := sin(_temps * (13.0 if bouge else 3.5) + phase) * (0.2 if bouge else 0.07)
	# Petit rebond pendant la marche.
	var saut := -absf(sin(_temps * 13.0 + phase)) * t * 0.22 if bouge else 0.0
	var centre := _centre(pos)
	# Élan vers la cible au corps à corps.
	if e["elan"] >= 0.0 and e["elan"] < 0.16:
		var vers: Vector2 = e["elan_vers"]
		centre += (vers - pos).normalized() * t * 0.5 * sin(PI * e["elan"] / 0.16)
	var r := t * 0.45
	var echelle := 1.0 - 0.6 * disparition
	# Ombre au sol.
	draw_set_transform(centre + Vector2(0, r * 0.95), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, r * 0.85 * echelle, Color(0, 0, 0, 0.35 * alpha))
	# Corps.
	var couleur: Color = COULEURS_CAMP[e["camp"]]
	if e["eclair"] >= 0.0:
		couleur = couleur.lerp(Color.WHITE, 0.75)
	couleur.a = alpha
	draw_set_transform(centre + Vector2(0, saut), angle, Vector2(echelle, echelle))
	var image := _image_de(e["type"])
	if image != null:
		draw_circle(Vector2(0, r * 0.75), r * 0.7, Color(COULEURS_CAMP[e["camp"]], 0.55 * alpha), false, 2.0)
		var modulation := Color(1, 1, 1, alpha)
		if e["eclair"] >= 0.0:
			modulation = Color(1.6, 1.6, 1.6, alpha)
		draw_texture_rect(image, Rect2(-r * 1.2, -r * 1.2, r * 2.4, r * 2.4), false, modulation)
	else:
		_dessiner_forme(str(e["forme"]), int(e["camp"]), r, couleur)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Barre de vie, seulement quand l'unité est blessée.
	var vie: float = e["vie"]
	if vie < float(e["vie_max"]) and alpha > 0.0:
		var ratio := clampf(vie / float(e["vie_max"]), 0.0, 1.0)
		var largeur := t * 1.1
		var coin := centre + Vector2(-largeur / 2.0, -r * 1.55 + saut)
		draw_rect(Rect2(coin, Vector2(largeur, 3.0)), Color(0, 0, 0, 0.7 * alpha))
		draw_rect(Rect2(coin, Vector2(largeur * ratio, 3.0)), _couleur_vie(ratio, alpha))


## Dessine une forme centrée sur (0, 0).
func _dessiner_forme(forme: String, camp: int, r: float, couleur: Color) -> void:
	var contour := couleur.darkened(0.45)
	match forme:
		"carre":
			var rect := Rect2(-r * 0.85, -r * 0.85, r * 1.7, r * 1.7)
			draw_rect(rect, couleur)
			draw_rect(rect, contour, false, 1.5)
		"triangle":
			var sens := -1.0 if camp == Combat.BLEU else 1.0
			var points := PackedVector2Array([
				Vector2(0, r * 1.05 * sens),
				Vector2(-r * 0.95, -r * 0.8 * sens),
				Vector2(r * 0.95, -r * 0.8 * sens),
			])
			draw_colored_polygon(points, couleur)
			points.append(points[0])
			draw_polyline(points, contour, 1.5)
		_:
			draw_circle(Vector2.ZERO, r * 0.9, couleur)
			draw_arc(Vector2.ZERO, r * 0.9, 0.0, TAU, 20, contour, 1.5)


## Un mur : un cube vu de dessus et de face, couleur sable.
func _dessiner_mur(cases: Array, t: float, alpha: float) -> void:
	if cases.is_empty():
		return
	var coin_min: Vector2i = cases[0]
	var coin_max: Vector2i = cases[0]
	for c in cases:
		var v: Vector2i = c
		coin_min = Vector2i(mini(coin_min.x, v.x), mini(coin_min.y, v.y))
		coin_max = Vector2i(maxi(coin_max.x, v.x), maxi(coin_max.y, v.y))
	var rect := Rect2(_origine() + Vector2(coin_min) * t, Vector2(coin_max - coin_min + Vector2i.ONE) * t).grow(-1.5)
	if _image_mur != null:
		draw_texture_rect(_image_mur, rect, false, Color(1, 1, 1, alpha))
		return
	var dessus := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.7))
	var face := Rect2(rect.position + Vector2(0, rect.size.y * 0.7), Vector2(rect.size.x, rect.size.y * 0.3))
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.3 * alpha))
	draw_rect(dessus, Color(COULEUR_MUR.lightened(0.15), alpha))
	draw_rect(face, Color(COULEUR_MUR.darkened(0.3), alpha))
	draw_rect(rect, Color(COULEUR_MUR.darkened(0.55), alpha), false, 1.5)


func _dessiner_effet(effet: Dictionary, t: float) -> void:
	var k := clampf((effet["age"] - effet["delai"]) / effet["duree"], 0.0, 1.0)
	match effet["type"]:
		"fleche":
			var de := _centre(effet["de"])
			var vers := _centre(effet["vers"])
			var pos := de.lerp(vers, k)
			var direction := (vers - de).normalized()
			var couleur: Color = COULEURS_CAMP[effet["camp"]].lightened(0.6)
			draw_line(pos - direction * t * 0.9, pos, couleur, 2.0)
			draw_circle(pos, 2.0, Color.WHITE)
		"coup":
			var centre := _centre(effet["pos"])
			var angle := (_centre(effet["pos"]) - _centre(effet["de"])).angle()
			draw_arc(centre, t * (0.5 + 0.3 * k), angle - 0.9, angle + 0.9, 10, Color(1, 1, 1, 1.0 - k), 2.5)
		"degats":
			# Le chiffre suit l'unité touchée (ou reste où elle est tombée).
			var pos: Vector2 = effet["pos"]
			if _unites.has(effet["id"]):
				pos = _unites[effet["id"]]["pos"]
			var base := _centre(pos) + Vector2(-t * 2.0 + effet["decalage"] * t * 0.45, -t * 0.9 - k * t * 1.0)
			var taille_police := int(maxf(13.0, t * 0.6))
			draw_string(_police, base, effet["texte"], HORIZONTAL_ALIGNMENT_CENTER, t * 4.0, taille_police, Color(1.0, 0.9, 0.35, 1.0 - k * k))


func _dessiner_apercu(t: float) -> void:
	if _survol.x < 0 or type_apercu == "" or _survol.y < _lignes - _lignes_par_camp:
		return
	if type_apercu == "mur":
		var cases: Array = []
		for dy in _taille_mur:
			for dx in _taille_mur:
				cases.append(_survol + Vector2i(dx, dy))
		_dessiner_mur(cases, t, 0.4)
		return
	var forme := str(_troupes.get(type_apercu, {}).get("forme", "cercle"))
	draw_set_transform(_centre(Vector2(_survol)), 0.0, Vector2.ONE)
	_dessiner_forme(forme, Combat.BLEU, t * 0.45, Color(COULEURS_CAMP[0], 0.45))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _dessiner_fin() -> void:
	var lignes_texte := texte_fin.split("\n")
	var hauteur := 60.0 + 46.0 * lignes_texte.size()
	var bandeau := Rect2(Vector2(0, (size.y - hauteur) / 2.0), Vector2(size.x, hauteur))
	draw_rect(bandeau, Color(0, 0, 0, 0.78))
	for i in lignes_texte.size():
		var taille_police := 46 if i == 0 else 24
		var y := bandeau.position.y + 66.0 + i * 46.0
		draw_string(_police, Vector2(0, y), lignes_texte[i], HORIZONTAL_ALIGNMENT_CENTER, size.x, taille_police)


# --- Outils ------------------------------------------------------------------

func _taille_case() -> float:
	return minf(size.x / _colonnes, size.y / _lignes)


func _origine() -> Vector2:
	var t := _taille_case()
	return ((size - Vector2(_colonnes, _lignes) * t) / 2.0).floor()


## Centre, en pixels, d'une position de grille (qui peut être entre deux cases).
func _centre(position_grille: Vector2) -> Vector2:
	return _origine() + (position_grille + Vector2(0.5, 0.5)) * _taille_case()


func _image_de(type_troupe: String) -> Texture2D:
	if not _images.has(type_troupe):
		_images[type_troupe] = _charger_image(str(_troupes.get(type_troupe, {}).get("image", "")))
	return _images[type_troupe]


func _charger_image(chemin: String) -> Texture2D:
	if chemin == "" or not ResourceLoader.exists(chemin):
		return null
	return load(chemin) as Texture2D


func _couleur_vie(ratio: float, alpha: float) -> Color:
	var c := Color(0.35, 0.85, 0.35)
	if ratio <= 0.25:
		c = Color(0.95, 0.3, 0.3)
	elif ratio <= 0.5:
		c = Color(0.95, 0.75, 0.25)
	c.a = alpha
	return c
