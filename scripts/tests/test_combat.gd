extends Control
## Vérifications automatiques du moteur de combat, puis le résumé du combat de
## démonstration (qui meurt, quand, qui gagne). Tout s'écrit à l'écran et dans le
## panneau « Sortie » de Godot. Aucun affichage graphique : on teste la logique seule.
## Pour la lancer : ouvrir scenes/test_combat.tscn puis F6.

const COULEUR_CAMP := ["#6fa8ff", "#ff7070"]
const NOM_CAMP := ["bleu", "rouge"]

var _lignes: Array[String] = []
var _reussis := 0
var _total := 0


func _ready() -> void:
	var donnees := Donnees.charger()
	_ecrire("[b]VÉRIFICATIONS AUTOMATIQUES[/b]")
	_verifier_donnees(donnees)
	_verifier_moteur()
	if donnees != null:
		_verifier_determinisme(donnees)
	var couleur := "#5fd35f" if _reussis == _total else "#ff5050"
	_ecrire("[b][color=%s]Résultat : %d/%d OK[/color][/b]" % [couleur, _reussis, _total])
	if donnees != null:
		_ecrire("")
		_raconter_combat_de_demo(donnees)
	_afficher()


# --- Vérifications -----------------------------------------------------------

func _verifier_donnees(donnees: Donnees) -> void:
	_verifier("Les fichiers de data/ se chargent", donnees != null,
		"un fichier est illisible : regarde les erreurs en rouge dans Sortie")
	if donnees == null:
		return
	var problemes := donnees.problemes()
	_verifier("Chaque troupe et structure a toutes ses stats", problemes.is_empty(),
		", ".join(PackedStringArray(problemes)))
	_verifier("Au moins une troupe, et le mur",
		donnees.troupes.size() >= 1 and donnees.structures.has("mur"))


## Ces tests utilisent leurs propres stats (pas celles de data/) : ils restent
## valables même quand on modifie l'équilibrage.
func _verifier_moteur() -> void:
	var t := _donnees_de_test()

	# Placement : chaque camp voit le terrain de son côté.
	var c := Combat.new(t, _armee([["soldat", Vector2i(0, 0)]]), _armee([["soldat", Vector2i(0, 0)]]))
	var bleu := c.unites[0]
	var rouge := c.unites[1]
	_verifier("Placement : chaque camp place de son côté du terrain",
		bleu.cellule == Vector2i(0, 8) and rouge.cellule == Vector2i(8, 5),
		"bleu en %s, rouge en %s" % [bleu.cellule, rouge.cellule])
	_verifier("Placement : les 2 lignes du milieu sont interdites",
		not c.dans_zone(Combat.BLEU, Vector2i(4, 7)) and not c.dans_zone(Combat.ROUGE, Vector2i(4, 6))
		and c.dans_zone(Combat.BLEU, Vector2i(4, 8)) and c.dans_zone(Combat.ROUGE, Vector2i(4, 5)))

	# Portée 1 : contact, diagonales comprises.
	_verifier("Portée 1 : frappe au contact, diagonales comprises",
		bleu.a_portee_de(bleu.cellule + Vector2i(1, -1)) and not bleu.a_portee_de(bleu.cellule + Vector2i(0, -2)))

	# Déplacement : une case par tour vers l'ennemi.
	c = Combat.new(t, _armee([["soldat", Vector2i(4, 0)]]), _armee([["soldat", Vector2i(4, 0)]]))
	bleu = c.unites[0]
	rouge = c.unites[1]
	c.jouer_tour()
	_verifier("Déplacement : une case par tour vers l'ennemi",
		bleu.cellule == Vector2i(4, 7) and rouge.cellule == Vector2i(4, 6),
		"bleu en %s, rouge en %s" % [bleu.cellule, rouge.cellule])

	# Attaques simultanées : deux soldats identiques s'entretuent.
	var r := c.simuler()
	_verifier("Attaques simultanées : deux soldats identiques s'entretuent (manche nulle)",
		r["gagnant"] == Combat.NUL and r["raison"] == "elimination",
		"résultat : %s" % str(r))

	# Vitesse 0,5 : une case tous les deux tours.
	c = Combat.new(t, _armee([["lent", Vector2i(4, 5)]]), _armee([["soldat", Vector2i(4, 5)]]))
	var lent := c.unites[0]
	var positions := []
	for i in 4:
		c.jouer_tour()
		positions.append(lent.cellule.y)
	_verifier("Vitesse 0,5 : une case tous les deux tours",
		positions == [13, 12, 12, 11], "lignes successives : %s" % str(positions))

	# Portée 4 : le tireur frappe de loin sans bouger.
	c = Combat.new(t, _armee([["tireur", Vector2i(4, 0)]]), _armee([["soldat", Vector2i(4, 0)]]))
	var tireur := c.unites[0]
	rouge = c.unites[1]
	c.jouer_tour()
	_verifier("Portée 4 : le tireur frappe de loin sans bouger",
		tireur.cellule == Vector2i(4, 8) and rouge.vie == 80,
		"tireur en %s, vie du rouge : %d" % [tireur.cellule, rouge.vie])

	# Mur : la troupe contourne au lieu de foncer dedans.
	var murs_bleus := [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]
	c = Combat.new(t, _armee([["soldat", Vector2i(4, 1)]], murs_bleus), _armee([["soldat", Vector2i(4, 0)]]))
	bleu = c.unites[0]
	c.jouer_tour()
	var contourne := bleu.cellule.y == 9 and (bleu.cellule.x == 3 or bleu.cellule.x == 5)
	var jamais_dans_un_mur := true
	while c.resultat.is_empty():
		c.jouer_tour()
		for u in c.unites:
			if c.murs.has(u.cellule):
				jamais_dans_un_mur = false
	_verifier("Mur : la troupe le contourne par le côté",
		contourne, "après le tour 1, le soldat bleu est en %s" % [bleu.cellule])
	_verifier("Mur : personne ne traverse un mur, et le combat se termine",
		jamais_dans_un_mur and c.resultat["raison"] == "elimination")

	# Limite de tours : deux camps enfermés par leurs murs ne peuvent pas se battre.
	var bleu_enferme := _armee([["soldat", Vector2i(0, 5)]], [Vector2i(0, 4), Vector2i(1, 5)])
	var rouge_enferme := _armee([["soldat", Vector2i(0, 5)], ["soldat", Vector2i(1, 5)]],
		[Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 5)])
	c = Combat.new(t, bleu_enferme, rouge_enferme)
	r = c.simuler()
	_verifier("Limite de 50 tours : gagne le camp qui a le plus de vie",
		r["raison"] == "limite_de_tours" and r["tours"] == 50 and r["gagnant"] == Combat.ROUGE,
		"résultat : %s" % str(r))

	# Murs : 4 maximum par joueur.
	var cinq_murs := [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]
	c = Combat.new(t, _armee([["soldat", Vector2i(8, 0)]], cinq_murs), _armee([["soldat", Vector2i(0, 0)]]))
	_verifier("Murs : 4 maximum par joueur", c.murs.size() == 4, "%d murs posés" % c.murs.size())

	# Bac à sable : murs illimités.
	c = Combat.new(t, _armee([["soldat", Vector2i(8, 0)]], cinq_murs), _armee([["soldat", Vector2i(0, 0)]]), true, false)
	_verifier("Bac à sable : murs illimités", c.murs.size() == 5, "%d murs posés" % c.murs.size())

	# Mur de taille 2 : un carré de 2 x 2 cases.
	var t2 := _donnees_de_test(14, 2)
	c = Combat.new(t2, _armee([["soldat", Vector2i(8, 0)]], [Vector2i(0, 4)]), _armee([["soldat", Vector2i(0, 0)]]))
	_verifier("Mur de taille 2 : il couvre 4 cases",
		c.murs.size() == 4 and c.blocs_murs.size() == 1
		and c.murs.has(Vector2i(0, 12)) and c.murs.has(Vector2i(1, 13)),
		"%d cases de mur" % c.murs.size())

	# Cadence : une attaque tous les 3 tours, sans bouger pendant la recharge.
	var t3 := _donnees_de_test(12, 1)
	c = Combat.new(t3, _armee([["cogneur", Vector2i(4, 0)]]), _armee([["sac", Vector2i(4, 0)]]))
	var cogneur := c.unites[0]
	var sac := c.unites[1]
	for i in 7:
		c.jouer_tour()
	_verifier("Cadence 3 : 3 coups en 7 tours, sans bouger entre deux coups",
		sac.vie == 970 and cogneur.cellule == Vector2i(4, 6),
		"vie du sac : %d, cogneur en %s" % [sac.vie, cogneur.cellule])

	# Conversions de cases : aller-retour entre case vue par un camp et case réelle.
	var terrain := Terrain.new(t)
	var aller_retour_ok := true
	for camp in [Combat.BLEU, Combat.ROUGE]:
		for case_camp in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(8, 5)]:
			if terrain.vers_camp(camp, terrain.vers_grille(camp, case_camp)) != case_camp:
				aller_retour_ok = false
	_verifier("Terrain : conversions de cases dans les deux sens", aller_retour_ok)


func _verifier_determinisme(donnees: Donnees) -> void:
	var premier_type: String = donnees.troupes.keys()[0]
	var groupe := Formations.en_ligne(donnees, premier_type, 3, 0)
	_verifier("Formations : un groupe en ligne a le bon nombre d'unités",
		groupe["cases"].size() == int(donnees.troupes[premier_type]["unites_par_carte"]))
	var c1 := _combat_demo(donnees)
	var c2 := _combat_demo(donnees)
	_verifier("combats_test.json : le combat de démo se charge (des troupes des deux côtés)",
		c1.unites.any(func(u: Unite) -> bool: return u.camp == Combat.BLEU)
		and c1.unites.any(func(u: Unite) -> bool: return u.camp == Combat.ROUGE))
	var r1 := c1.simuler()
	var r2 := c2.simuler()
	_verifier("Pas de hasard : même placement, même combat",
		str(c1.historique) == str(c2.historique) and str(r1) == str(r2))
	_verifier("Le combat de démonstration se termine",
		not r1.is_empty() and int(r1["tours"]) <= c1.tours_max)


func _verifier(description: String, condition: bool, detail: String = "") -> void:
	_total += 1
	if condition:
		_reussis += 1
		_ecrire("[color=#5fd35f]OK[/color]  " + description)
	else:
		var suite := ("  (" + detail + ")") if detail != "" else ""
		_ecrire("[color=#ff5050]ÉCHEC[/color]  " + description + suite)


# --- Données et armées de test -------------------------------------------------

## Petit terrain de test : 9 colonnes, 6 lignes par camp ; avec 14 lignes il y a
## 2 lignes neutres au milieu, avec 12 les deux camps se touchent.
func _donnees_de_test(lignes: int = 14, taille_mur: int = 1) -> Donnees:
	var d := Donnees.new()
	d.troupes = {
		"soldat": {"nom": "Soldat", "forme": "cercle", "cout": 3, "unites_par_carte": 1,
			"vie": 100, "degats": 20, "portee": 1, "vitesse": 1},
		"lent": {"nom": "Lent", "forme": "carre", "cout": 3, "unites_par_carte": 1,
			"vie": 100, "degats": 20, "portee": 1, "vitesse": 0.5},
		"tireur": {"nom": "Tireur", "forme": "triangle", "cout": 3, "unites_par_carte": 1,
			"vie": 60, "degats": 20, "portee": 4, "vitesse": 1},
		"cogneur": {"nom": "Cogneur", "forme": "carre", "cout": 3, "unites_par_carte": 1,
			"vie": 1000, "degats": 10, "cadence": 3, "portee": 1, "vitesse": 1},
		"sac": {"nom": "Sac", "forme": "cercle", "cout": 3, "unites_par_carte": 1,
			"vie": 1000, "degats": 0, "portee": 1, "vitesse": 0},
	}
	d.structures = {"mur": {"nom": "Mur", "cout": 1, "max_par_joueur": 4, "taille": taille_mur}}
	d.regles = {
		"terrain": {"colonnes": 9, "lignes": lignes, "lignes_par_camp": 6},
		"combat": {"tours_max": 50},
	}
	return d


## Armée de test : une liste de [type, case] (une unité par groupe) et des murs.
func _armee(unites: Array, murs: Array = []) -> Dictionary:
	var groupes := []
	for u in unites:
		groupes.append({"type": u[0], "cases": [u[1]]})
	return {"groupes": groupes, "murs": murs}


## Le combat de démonstration, lu dans data/combats_test.json (bloc « demo »).
func _combat_demo(donnees: Donnees) -> Combat:
	var demo: Dictionary = Donnees.lire_fichier("combats_test.json").get("demo", {})
	return Combat.new(donnees, demo.get("bleu", {}), demo.get("rouge", {}), true, false)


# --- Résumé du combat de démonstration -----------------------------------------

func _raconter_combat_de_demo(donnees: Donnees) -> void:
	var combat := _combat_demo(donnees)
	var nombre := [0, 0]
	for u in combat.toutes_les_unites:
		nombre[u.camp] += 1
	_ecrire("[b]COMBAT DE DÉMONSTRATION[/b] (data/combats_test.json, stats de data/troupes.json)")
	_ecrire("Au départ : %d bleus, %d rouges, %d murs." % [nombre[0], nombre[1], combat.blocs_murs.size()])
	combat.simuler()
	var secondes := donnees.regle_decimale("affichage", "secondes_par_tour", 0.1)
	for i in combat.historique.size():
		for ev in combat.historique[i]:
			if ev["type"] == "mort":
				_ecrire("  %.1f s : %s est éliminé" % [(i + 1) * secondes, _nom(combat.unite_par_id(ev["unite"]))])
	_ecrire("")
	_ecrire("[b]" + _decrire_resultat(combat.resultat) + "[/b]")


func _decrire_resultat(r: Dictionary) -> String:
	var texte := "Manche nulle"
	if r["gagnant"] != Combat.NUL:
		texte = "Victoire %s" % NOM_CAMP[r["gagnant"]].to_upper()
	texte += " en %d tours" % r["tours"]
	if r["raison"] == "limite_de_tours":
		texte += " (limite atteinte : départage aux points de vie)"
	var vie: Array = r["vie_restante"]
	var nombre: Array = r["unites_restantes"]
	texte += ". Restent : %d bleus (%d PV), %d rouges (%d PV)." % [nombre[0], vie[0], nombre[1], vie[1]]
	return texte


func _nom(u: Unite) -> String:
	return "[color=%s]%s %s %d[/color]" % [COULEUR_CAMP[u.camp], u.nom, NOM_CAMP[u.camp], u.id]


# --- Sortie -----------------------------------------------------------------

func _ecrire(ligne: String) -> void:
	_lignes.append(ligne)


func _afficher() -> void:
	var texte := "\n".join(PackedStringArray(_lignes))
	print_rich(texte)
	var zone := RichTextLabel.new()
	zone.bbcode_enabled = true
	zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	zone.add_theme_font_size_override("normal_font_size", 20)
	zone.add_theme_font_size_override("bold_font_size", 22)
	zone.text = texte
	add_child(zone)
