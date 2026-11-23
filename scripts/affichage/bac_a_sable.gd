extends Control
## Bac à sable : on place librement ses troupes bleues (sans limite) face à la
## compo rouge fixe du bloc « demo » de data/combats_test.json, puis on lance le
## combat. Il s'arrête tout seul quand un camp n'a plus personne.
## L'écran ne décide rien du combat : il fait avancer Combat et l'affiche.

enum Etat { PLACEMENT, COMBAT, FIN }

const FICHIER_COMBATS := "combats_test.json"
const NOM_COMBAT := "demo"
## Petite pause avant d'afficher le bandeau de fin (laisser finir les animations).
const ATTENTE_FIN := 0.6

var _donnees: Donnees
var _terrain: Terrain
var _rouge: Dictionary = {}
## Troupes bleues posées : [{"type": String, "case": Vector2i}], cases vues par le bleu.
var _bleus: Array = []
## Murs bleus posés : coin de chaque mur, vu par le bleu.
var _murs_bleus: Array[Vector2i] = []
var _taille_mur := 2
## Ce qu'on pose : un type de troupe ou "mur".
var _choix := ""
## Pendant un glissé : "poser" ou "effacer" (décidé au premier contact).
var _mode_glisser := "poser"

var _etat := Etat.PLACEMENT
var _combat: Combat
var _secondes_par_tour := 0.1
var _chrono := 0.0
var _attente_fin := -1.0

var _vue: VueTerrain
var _info: Label
var _aide: Label
var _palette: HBoxContainer
var _bouton_effacer: Button
var _bouton_action: Button


func _ready() -> void:
	_construire_interface()
	_donnees = Donnees.charger()
	if _donnees == null:
		_info.text = "Erreur : fichiers de data/ illisibles"
		return
	_terrain = Terrain.new(_donnees)
	_taille_mur = maxi(1, int(_donnees.structures.get("mur", {}).get("taille", 1)))
	_secondes_par_tour = maxf(0.02, _donnees.regle_decimale("affichage", "secondes_par_tour", 0.1))
	_vue.secondes_par_tour = _secondes_par_tour
	var demo: Dictionary = Donnees.lire_fichier(FICHIER_COMBATS).get(NOM_COMBAT, {})
	_rouge = demo.get("rouge", {})
	_charger_bleus(demo.get("bleu", {}))
	_remplir_palette()
	_retour_placement()


func _process(delta: float) -> void:
	if _etat == Etat.COMBAT:
		_chrono += delta
		var tours_joues := 0
		while _chrono >= _secondes_par_tour and _combat.resultat.is_empty() and tours_joues < 3:
			_chrono -= _secondes_par_tour
			tours_joues += 1
			_combat.jouer_tour()
			_vue.appliquer_tour(_combat.historique[_combat.historique.size() - 1])
		if tours_joues > 0:
			_maj_info()
		if not _combat.resultat.is_empty():
			_etat = Etat.FIN
			_attente_fin = ATTENTE_FIN
	elif _etat == Etat.FIN and _attente_fin >= 0.0:
		_attente_fin -= delta
		if _attente_fin < 0.0:
			_afficher_fin()


# --- Les trois moments : placement, combat, fin --------------------------------

func _retour_placement() -> void:
	_etat = Etat.PLACEMENT
	_attente_fin = -1.0
	_vue.mode_placement = true
	_montrer_palette(true)
	_bouton_effacer.visible = true
	_bouton_action.text = "Lancer le combat"
	_aide.text = "Touche ta zone (en bas) pour placer. Touche une troupe ou un mur pour l'enlever. Tu peux glisser le doigt."
	_maj_apercu()


func _lancer_combat() -> void:
	if _bleus.is_empty():
		_aide.text = "Place au moins une troupe avant de lancer le combat."
		return
	_combat = Combat.new(_donnees, _armee_bleue(), _rouge, true, false)
	_vue.preparer(_combat)
	_vue.mode_placement = false
	_etat = Etat.COMBAT
	_chrono = 0.0
	_montrer_palette(false)
	_bouton_effacer.visible = false
	_bouton_action.text = "Arrêter"
	_aide.text = "Le combat se joue tout seul."
	_maj_info()


## Public : utilisé aussi par l'outil de captures d'écran.
func lancer_combat() -> void:
	_lancer_combat()


func _afficher_fin() -> void:
	var r := _combat.resultat
	var texte := "Manche nulle"
	if r["gagnant"] == Combat.BLEU:
		texte = "Victoire BLEUE !"
	elif r["gagnant"] == Combat.ROUGE:
		texte = "Victoire ROUGE !"
	texte += "\nen %.1f secondes" % (r["tours"] * _secondes_par_tour)
	if r["raison"] == "limite_de_tours":
		texte += " (temps écoulé : départage aux PV)"
	_vue.texte_fin = texte
	_bouton_action.text = "Recommencer"
	_aide.text = "Recommencer garde ton placement : tu peux le modifier et relancer."
	print("Fin du combat : %s" % texte.replace("\n", " "))


## On cache la palette sans lui retirer sa place : le terrain garde la même taille.
func _montrer_palette(visible_ou_non: bool) -> void:
	_palette.modulate.a = 1.0 if visible_ou_non else 0.0
	for b in _palette.get_children():
		(b as Button).disabled = not visible_ou_non


func _sur_action() -> void:
	match _etat:
		Etat.PLACEMENT:
			_lancer_combat()
		_:
			_retour_placement()


func _sur_effacer() -> void:
	_bleus.clear()
	_murs_bleus.clear()
	_maj_apercu()


# --- Placement à la main --------------------------------------------------------

func _sur_case_touchee(cellule: Vector2i, debut: bool) -> void:
	if _etat != Etat.PLACEMENT:
		return
	var case_camp := _terrain.vers_camp(Combat.BLEU, cellule)
	if debut:
		_mode_glisser = "effacer" if _objet_en(case_camp) else "poser"
	var change := false
	if _mode_glisser == "effacer":
		change = _effacer_en(case_camp)
	else:
		change = _poser_en(case_camp)
	if change:
		_maj_apercu()


func _poser_en(case_camp: Vector2i) -> bool:
	if _choix == "mur":
		for c in Terrain.cases_mur_camp(case_camp, _taille_mur):
			if not _terrain.dans_zone_camp(c) or _objet_en(c):
				return false
		_murs_bleus.append(case_camp)
		return true
	if _choix == "" or not _terrain.dans_zone_camp(case_camp) or _objet_en(case_camp):
		return false
	_bleus.append({"type": _choix, "case": case_camp})
	return true


func _effacer_en(case_camp: Vector2i) -> bool:
	for i in _bleus.size():
		if _bleus[i]["case"] == case_camp:
			_bleus.remove_at(i)
			return true
	for i in _murs_bleus.size():
		if case_camp in Terrain.cases_mur_camp(_murs_bleus[i], _taille_mur):
			_murs_bleus.remove_at(i)
			return true
	return false


## Y a-t-il déjà une troupe bleue ou un mur bleu sur cette case ?
func _objet_en(case_camp: Vector2i) -> bool:
	for b in _bleus:
		if b["case"] == case_camp:
			return true
	for coin in _murs_bleus:
		if case_camp in Terrain.cases_mur_camp(coin, _taille_mur):
			return true
	return false


func _armee_bleue() -> Dictionary:
	var groupes := []
	for b in _bleus:
		groupes.append({"type": b["type"], "cases": [b["case"]]})
	return {"groupes": groupes, "murs": _murs_bleus.duplicate()}


func _charger_bleus(armee: Dictionary) -> void:
	_bleus.clear()
	_murs_bleus.clear()
	for groupe in armee.get("groupes", []):
		for c in groupe.get("cases", []):
			_bleus.append({"type": str(groupe.get("type", "")), "case": Combat._en_case(c)})
	for c in armee.get("murs", []):
		_murs_bleus.append(Combat._en_case(c))


## Le terrain montre le placement en cours (combat créé mais pas lancé).
func _maj_apercu() -> void:
	var apercu := Combat.new(_donnees, _armee_bleue(), _rouge, false, false)
	_vue.preparer(apercu)
	_combat = apercu
	_maj_info()


# --- Textes ------------------------------------------------------------------

func _maj_info() -> void:
	if _combat == null:
		return
	var nombre := [0, 0]
	for u in _combat.unites:
		nombre[u.camp] += 1
	if _etat == Etat.PLACEMENT:
		_info.text = "Bleus : %d troupes, %d murs     Rouges : %d troupes" % [
			nombre[0], _murs_bleus.size(), nombre[1]]
	else:
		_info.text = "Bleus : %d en vie     Rouges : %d en vie" % [nombre[0], nombre[1]]


# --- Construction de l'écran ---------------------------------------------------

func _construire_interface() -> void:
	var colonne := VBoxContainer.new()
	colonne.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	colonne.add_theme_constant_override("separation", 6)
	add_child(colonne)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 26)
	colonne.add_child(_info)

	_vue = VueTerrain.new()
	_vue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vue.case_touchee.connect(_sur_case_touchee)
	colonne.add_child(_vue)

	_aide = Label.new()
	_aide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aide.add_theme_font_size_override("font_size", 19)
	_aide.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	colonne.add_child(_aide)

	_palette = HBoxContainer.new()
	_palette.add_theme_constant_override("separation", 8)
	colonne.add_child(_palette)

	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 8)
	colonne.add_child(ligne)
	_bouton_effacer = _bouton(ligne, "Tout effacer", _sur_effacer)
	_bouton_action = _bouton(ligne, "Lancer le combat", _sur_action)
	_bouton_action.size_flags_stretch_ratio = 2.0


## Un bouton par type de troupe (lu dans data/troupes.json), plus le mur.
func _remplir_palette() -> void:
	var groupe := ButtonGroup.new()
	var premier := true
	for cle in _donnees.troupes:
		var troupe: Dictionary = _donnees.troupes[cle]
		var icone: Texture2D = _image(str(troupe.get("image", "")))
		if icone == null:
			icone = _icone(str(troupe["forme"]), VueTerrain.COULEURS_CAMP[0])
		_ajouter_choix(groupe, cle, str(troupe["nom"]), icone, premier)
		premier = false
	var mur: Dictionary = _donnees.structures.get("mur", {})
	var icone_mur: Texture2D = _image(str(mur.get("image", "")))
	if icone_mur == null:
		icone_mur = _icone("cube", VueTerrain.COULEUR_MUR)
	_ajouter_choix(groupe, "mur", str(mur.get("nom", "Mur")), icone_mur, false)


## L'image d'une troupe si Adrian en a mis une (sinon null).
func _image(chemin: String) -> Texture2D:
	if chemin == "" or not ResourceLoader.exists(chemin):
		return null
	return load(chemin) as Texture2D


func _ajouter_choix(groupe: ButtonGroup, cle: String, nom: String, icone: Texture2D, choisi: bool) -> void:
	var b := Button.new()
	b.text = nom
	b.icon = icone
	b.expand_icon = true
	b.toggle_mode = true
	b.button_group = groupe
	b.custom_minimum_size = Vector2(0, 80)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	b.toggled.connect(func(actif: bool) -> void:
		if actif:
			_choix = cle
			_vue.type_apercu = cle)
	_palette.add_child(b)
	if choisi:
		b.button_pressed = true


func _bouton(parent: Control, texte: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Petite image pour les boutons : la forme de la troupe, ou un cube pour le mur.
func _icone(forme: String, couleur: Color) -> ImageTexture:
	var cote := 40
	var image := Image.create_empty(cote, cote, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in cote:
		for x in cote:
			var px := x + 0.5
			var py := y + 0.5
			var teinte := couleur
			var dedans := false
			match forme:
				"carre":
					dedans = px > 7 and px < 33 and py > 7 and py < 33
				"triangle":
					var k := (py - 5.0) / 30.0
					dedans = k >= 0.0 and k <= 1.0 and absf(px - 20.0) <= 16.0 * k
				"cube":
					dedans = px > 5 and px < 35 and py > 5 and py < 35
					teinte = couleur.lightened(0.15) if py < 26 else couleur.darkened(0.3)
				_:
					dedans = Vector2(px, py).distance_to(Vector2(20, 20)) < 15.0
			if dedans:
				image.set_pixel(x, y, teinte)
	return ImageTexture.create_from_image(image)
