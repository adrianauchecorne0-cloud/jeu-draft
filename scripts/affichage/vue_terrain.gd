class_name VueTerrain
extends Control
## Dessine le terrain et anime un tour de combat.
## Ne décide rien : elle recopie l'état de départ du Combat, puis rejoue les
## événements de chaque tour (attaques, morts, déplacements) qu'on lui donne.

const COULEURS_CAMP := [Color("4d8dff"), Color("ff5a5a")]
const COULEURS_ZONE := [Color(0.13, 0.19, 0.33), Color(0.33, 0.14, 0.17)]
const COULEUR_NEUTRE := Color(0.19, 0.19, 0.22)
const COULEUR_GRILLE := Color(1, 1, 1, 0.07)
const COULEUR_MUR := Color(0.58, 0.58, 0.62)
## Part du tour consacrée aux attaques ; le reste sert aux déplacements.
const PART_ATTAQUES := 0.5

## Avancement de l'animation du tour en cours : 0 = début, 1 = fini.
var progression := 1.0
## Message affiché par-dessus le terrain à la fin du combat (vide = rien).
var texte_fin := ""

var _colonnes := 9
var _lignes := 14
var _lignes_par_camp := 6
var _murs: Dictionary = {}
## Une entrée par unité (id) : ce qu'il faut pour la dessiner.
var _unites: Dictionary = {}
## Les attaques du tour en cours : {"de": case, "vers": case, "camp": int}.
var _attaques: Array = []
var _police: Font


func _ready() -> void:
	_police = ThemeDB.fallback_font
	resized.connect(queue_redraw)


## À appeler juste après Combat.new(), avant le premier tour.
func preparer(combat: Combat) -> void:
	_colonnes = combat.colonnes
	_lignes = combat.lignes
	_lignes_par_camp = combat.lignes_par_camp
	_murs = combat.murs.duplicate()
	_unites.clear()
	_attaques.clear()
	for u in combat.toutes_les_unites:
		_unites[u.id] = {
			"camp": u.camp,
			"forme": u.forme,
			"vie_max": u.vie_max,
			"vie_debut": u.vie,
			"vie_fin": u.vie,
			"chemin": [u.cellule],
			"meurt": false,
			"mort": false,
		}
	progression = 1.0
	texte_fin = ""
	queue_redraw()


## Lance l'animation d'un tour à partir de ses événements (Combat.historique).
func debut_tour(evenements: Array) -> void:
	for id in _unites:
		var e: Dictionary = _unites[id]
		if e["meurt"]:
			e["mort"] = true
			e["meurt"] = false
		var chemin: Array = e["chemin"]
		e["chemin"] = [chemin[chemin.size() - 1]]
		e["vie_debut"] = e["vie_fin"]
	_attaques.clear()
	for ev in evenements:
		match ev["type"]:
			"attaque":
				var source: Dictionary = _unites[ev["source"]]
				var cible: Dictionary = _unites[ev["cible"]]
				cible["vie_fin"] = ev["vie_apres"]
				_attaques.append({"de": source["chemin"][0], "vers": cible["chemin"][0], "camp": source["camp"]})
			"mort":
				_unites[ev["unite"]]["meurt"] = true
			"deplacement":
				_unites[ev["unite"]]["chemin"].append(ev["vers"])
	progression = 0.0
	queue_redraw()


# --- Dessin ------------------------------------------------------------------

func _draw() -> void:
	var t := _taille_case()
	if t <= 0.0:
		return
	_dessiner_terrain(t)
	var p_attaque := clampf(progression / PART_ATTAQUES, 0.0, 1.0)
	var p_mouvement := clampf((progression - PART_ATTAQUES) / (1.0 - PART_ATTAQUES), 0.0, 1.0)
	for id in _unites:
		_dessiner_unite(_unites[id], t, p_attaque, p_mouvement)
	if progression < 1.0:
		for a in _attaques:
			_dessiner_attaque(a, t, p_attaque)
		for id in _unites:
			_dessiner_degats(_unites[id], t, p_attaque, p_mouvement)
	if texte_fin != "":
		_dessiner_fin()


func _dessiner_terrain(t: float) -> void:
	var o := _origine()
	for y in _lignes:
		var couleur := COULEUR_NEUTRE
		if y < _lignes_par_camp:
			couleur = COULEURS_ZONE[1]
		elif y >= _lignes - _lignes_par_camp:
			couleur = COULEURS_ZONE[0]
		draw_rect(Rect2(o + Vector2(0, y * t), Vector2(_colonnes * t, t)), couleur)
	for x in _colonnes + 1:
		draw_line(o + Vector2(x * t, 0), o + Vector2(x * t, _lignes * t), COULEUR_GRILLE, 1.0)
	for y in _lignes + 1:
		draw_line(o + Vector2(0, y * t), o + Vector2(_colonnes * t, y * t), COULEUR_GRILLE, 1.0)
	for c in _murs:
		var case_mur: Vector2i = c
		var r := Rect2(o + Vector2(case_mur) * t, Vector2(t, t)).grow(-3.0)
		draw_rect(r, COULEUR_MUR)
		draw_rect(r, COULEURS_CAMP[_murs[c]], false, 3.0)


func _dessiner_unite(e: Dictionary, t: float, p_attaque: float, p_mouvement: float) -> void:
	if e["mort"]:
		return
	var alpha := (1.0 - p_attaque) if e["meurt"] else 1.0
	var centre := _centre(_position_sur_chemin(e["chemin"], p_mouvement))
	var couleur: Color = COULEURS_CAMP[e["camp"]]
	couleur.a = alpha
	var r := t * 0.34
	match e["forme"]:
		"carre":
			draw_rect(Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), couleur)
		"triangle":
			# La pointe vise le camp adverse.
			var sens := -1.0 if e["camp"] == Combat.BLEU else 1.0
			var points := PackedVector2Array([
				centre + Vector2(0, r * 1.1 * sens),
				centre + Vector2(-r, -r * 0.9 * sens),
				centre + Vector2(r, -r * 0.9 * sens),
			])
			draw_colored_polygon(points, couleur)
		_:
			draw_circle(centre, r, couleur)
	# Barre de vie au-dessus de l'unité.
	var vie := lerpf(e["vie_debut"], e["vie_fin"], p_attaque)
	var ratio := clampf(vie / float(e["vie_max"]), 0.0, 1.0)
	var largeur := t * 0.8
	var coin := centre + Vector2(-largeur / 2.0, -t * 0.5 + 2.0)
	draw_rect(Rect2(coin, Vector2(largeur, 6)), Color(0, 0, 0, 0.6 * alpha))
	draw_rect(Rect2(coin, Vector2(largeur * ratio, 6)), _couleur_vie(ratio, alpha))


func _dessiner_attaque(a: Dictionary, t: float, p: float) -> void:
	if p >= 1.0:
		return
	var case_de: Vector2i = a["de"]
	var case_vers: Vector2i = a["vers"]
	var de := _centre(Vector2(case_de))
	var vers := _centre(Vector2(case_vers))
	var couleur: Color = COULEURS_CAMP[a["camp"]].lightened(0.55)
	if de.distance_to(vers) > t * 1.6:
		# Tir à distance : un projectile qui voyage avec une petite traînée.
		var pos := de.lerp(vers, p)
		draw_line(de.lerp(vers, maxf(0.0, p - 0.2)), pos, Color(couleur, 0.5), 3.0)
		draw_circle(pos, t * 0.08, couleur)
	else:
		# Corps à corps : un trait qui s'efface.
		couleur.a = 1.0 - p
		draw_line(de, vers, couleur, 5.0)


func _dessiner_degats(e: Dictionary, t: float, p_attaque: float, p_mouvement: float) -> void:
	var perte := int(e["vie_debut"]) - int(e["vie_fin"])
	if perte <= 0 or e["mort"]:
		return
	var case_depart: Vector2i = e["chemin"][0]
	var base := _centre(Vector2(case_depart)) + Vector2(-t, -t * 0.56 - p_attaque * t * 0.4)
	var couleur := Color(1.0, 0.88, 0.35, 1.0 - p_mouvement)
	draw_string(_police, base, "-%d" % perte, HORIZONTAL_ALIGNMENT_CENTER, t * 2.0, int(t * 0.34), couleur)


func _dessiner_fin() -> void:
	var lignes_texte := texte_fin.split("\n")
	var hauteur := 70.0 + 50.0 * lignes_texte.size()
	var bandeau := Rect2(Vector2(0, (size.y - hauteur) / 2.0), Vector2(size.x, hauteur))
	draw_rect(bandeau, Color(0, 0, 0, 0.78))
	for i in lignes_texte.size():
		var taille_police := 48 if i == 0 else 26
		var y := bandeau.position.y + 70.0 + i * 50.0
		draw_string(_police, Vector2(0, y), lignes_texte[i], HORIZONTAL_ALIGNMENT_CENTER, size.x, taille_police)


# --- Géométrie -----------------------------------------------------------------

func _taille_case() -> float:
	return floorf(minf(size.x / _colonnes, size.y / _lignes))


func _origine() -> Vector2:
	var t := _taille_case()
	return ((size - Vector2(_colonnes, _lignes) * t) / 2.0).floor()


## Centre, en pixels, d'une position de grille (qui peut être entre deux cases).
func _centre(position_grille: Vector2) -> Vector2:
	return _origine() + (position_grille + Vector2(0.5, 0.5)) * _taille_case()


func _position_sur_chemin(chemin: Array, p: float) -> Vector2:
	var depart: Vector2i = chemin[0]
	if chemin.size() == 1:
		return Vector2(depart)
	var etapes := chemin.size() - 1
	var x := p * etapes
	var i := mini(int(x), etapes - 1)
	var a: Vector2i = chemin[i]
	var b: Vector2i = chemin[i + 1]
	return Vector2(a).lerp(Vector2(b), x - i)


func _couleur_vie(ratio: float, alpha: float) -> Color:
	var c := Color(0.35, 0.85, 0.35)
	if ratio <= 0.25:
		c = Color(0.95, 0.3, 0.3)
	elif ratio <= 0.5:
		c = Color(0.95, 0.75, 0.25)
	c.a = alpha
	return c
