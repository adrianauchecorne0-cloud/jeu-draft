extends Control
## Étape 2 : regarder un combat se dérouler, tour par tour.
## Le combat vient de data/combats_test.json (bloc « demo »). Cet écran fait
## avancer le Combat et anime ce qui s'est passé ; il ne décide jamais rien.

const FICHIER_COMBATS := "combats_test.json"
const NOM_COMBAT := "demo"
## Durée d'un tour à vitesse x1, en secondes.
const DUREE_TOUR := 0.7
## Petite pause avant le premier tour, pour voir le placement de départ.
const ATTENTE_DEPART := 1.2
const VITESSES := [1.0, 2.0, 4.0]
const NOMS_FORMES := {"cercle": "rond", "carre": "carré", "triangle": "triangle"}

var _donnees: Donnees
var _armees: Dictionary = {}
var _combat: Combat
var _vue: VueTerrain
var _titre: Label
var _forces: RichTextLabel
var _legende: Label
var _bouton_lecture: Button
var _bouton_vitesse: Button

var _lecture := true
var _pas_force := false
var _indice_vitesse := 0
var _t := 1.0
var _attente := 0.0
var _fin_affichee := false


func _ready() -> void:
	_construire_interface()
	_donnees = Donnees.charger()
	if _donnees == null:
		_titre.text = "Erreur : fichiers de data/ illisibles"
		return
	_armees = Donnees.lire_fichier(FICHIER_COMBATS).get(NOM_COMBAT, {})
	if _armees.is_empty():
		_titre.text = "Erreur : combat « %s » absent de %s" % [NOM_COMBAT, FICHIER_COMBATS]
		return
	_legende.text = _texte_legende()
	_nouveau_combat()


func _process(delta: float) -> void:
	if _combat == null:
		return
	var vitesse: float = VITESSES[_indice_vitesse]
	if _attente > 0.0:
		if _lecture:
			_attente -= delta * vitesse
		return
	if _t < 1.0:
		if not _lecture and not _pas_force:
			return
		_t = minf(1.0, _t + delta * vitesse / DUREE_TOUR)
		_vue.progression = _t
		_vue.queue_redraw()
		if _t >= 1.0:
			_pas_force = false
			_maj_textes()
		return
	if not _combat.resultat.is_empty():
		if not _fin_affichee:
			_afficher_fin()
		return
	if _lecture:
		_demarrer_tour()


# --- Déroulement ---------------------------------------------------------------

func _nouveau_combat() -> void:
	_combat = Combat.new(_donnees, _armees.get("bleu", {}), _armees.get("rouge", {}))
	_vue.preparer(_combat)
	_t = 1.0
	_attente = ATTENTE_DEPART
	_fin_affichee = false
	_lecture = true
	_pas_force = false
	_bouton_lecture.text = "Pause"
	_maj_textes()


func _demarrer_tour() -> void:
	_combat.jouer_tour()
	_vue.debut_tour(_combat.historique[_combat.historique.size() - 1])
	_t = 0.0
	_maj_textes()


func _afficher_fin() -> void:
	_fin_affichee = true
	var r := _combat.resultat
	var texte := "Manche nulle"
	if r["gagnant"] == Combat.BLEU:
		texte = "Victoire BLEUE !"
	elif r["gagnant"] == Combat.ROUGE:
		texte = "Victoire ROUGE !"
	texte += "\nen %d tours" % r["tours"]
	if r["raison"] == "limite_de_tours":
		texte += " (départage aux PV)"
	_vue.texte_fin = texte
	_vue.queue_redraw()
	print("Fin de l'affichage : %s" % texte.replace("\n", " "))


# --- Boutons -----------------------------------------------------------------

func _sur_lecture() -> void:
	_lecture = not _lecture
	_pas_force = false
	_bouton_lecture.text = "Pause" if _lecture else "Lecture"


func _sur_tour_suivant() -> void:
	_lecture = false
	_bouton_lecture.text = "Lecture"
	_attente = 0.0
	if _t < 1.0:
		_pas_force = true
	elif _combat.resultat.is_empty():
		_demarrer_tour()
		_pas_force = true


func _sur_vitesse() -> void:
	_indice_vitesse = (_indice_vitesse + 1) % VITESSES.size()
	_bouton_vitesse.text = "x%d" % int(VITESSES[_indice_vitesse])


func _sur_rejouer() -> void:
	if _donnees != null and not _armees.is_empty():
		_nouveau_combat()


# --- Textes ------------------------------------------------------------------

func _maj_textes() -> void:
	if _combat.tour == 0:
		_titre.text = "Placement de départ"
	else:
		_titre.text = "Tour %d / %d" % [_combat.tour, _combat.tours_max]
	var nombre := [0, 0]
	var vie := [0, 0]
	for u in _combat.unites:
		nombre[u.camp] += 1
		vie[u.camp] += u.vie
	_forces.text = "[center][color=#6fa8ff]Bleus : %s, %d PV[/color]     [color=#ff7070]Rouges : %s, %d PV[/color][/center]" % [
		_unites_texte(nombre[0]), vie[0], _unites_texte(nombre[1]), vie[1]]


func _unites_texte(n: int) -> String:
	return "%d unité" % n if n <= 1 else "%d unités" % n


func _texte_legende() -> String:
	var morceaux := PackedStringArray()
	for cle in _donnees.troupes:
		var troupe: Dictionary = _donnees.troupes[cle]
		morceaux.append("%s = %s" % [NOMS_FORMES.get(troupe["forme"], troupe["forme"]), troupe["nom"]])
	morceaux.append("gris = Mur")
	return "   ".join(morceaux)


# --- Construction de l'écran ---------------------------------------------------

func _construire_interface() -> void:
	var colonne := VBoxContainer.new()
	colonne.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	colonne.add_theme_constant_override("separation", 6)
	add_child(colonne)

	_titre = Label.new()
	_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titre.add_theme_font_size_override("font_size", 34)
	colonne.add_child(_titre)

	_forces = RichTextLabel.new()
	_forces.bbcode_enabled = true
	_forces.fit_content = true
	_forces.scroll_active = false
	_forces.add_theme_font_size_override("normal_font_size", 22)
	colonne.add_child(_forces)

	_legende = Label.new()
	_legende.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legende.add_theme_font_size_override("font_size", 20)
	_legende.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	colonne.add_child(_legende)

	_vue = VueTerrain.new()
	_vue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(_vue)

	var boutons := HBoxContainer.new()
	boutons.add_theme_constant_override("separation", 8)
	colonne.add_child(boutons)
	_bouton_lecture = _bouton(boutons, "Pause", _sur_lecture)
	_bouton(boutons, "Tour +1", _sur_tour_suivant)
	_bouton_vitesse = _bouton(boutons, "x1", _sur_vitesse)
	_bouton(boutons, "Rejouer", _sur_rejouer)


func _bouton(parent: Control, texte: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 28)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b
