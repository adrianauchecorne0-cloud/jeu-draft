class_name Terrain
extends RefCounted
## Dimensions du terrain et conversions de cases. Logique pure.
##
## Deux façons de désigner une case :
## - case réelle (x, y) : (0, 0) en haut à gauche de l'écran ;
## - case vue par un camp (colonne, rang) : colonne 0 = sa gauche, rang 0 = sa ligne
##   la plus proche du milieu. Le rouge est tourné de 180° par rapport au bleu.

const BLEU := 0
const ROUGE := 1

var colonnes: int
var lignes: int
var lignes_par_camp: int


func _init(donnees: Donnees) -> void:
	colonnes = donnees.regle_entiere("terrain", "colonnes")
	lignes = donnees.regle_entiere("terrain", "lignes")
	lignes_par_camp = donnees.regle_entiere("terrain", "lignes_par_camp")


## Case vue par un camp -> case réelle.
func vers_grille(camp: int, case_camp: Vector2i) -> Vector2i:
	if camp == BLEU:
		return Vector2i(case_camp.x, lignes - lignes_par_camp + case_camp.y)
	return Vector2i(colonnes - 1 - case_camp.x, lignes_par_camp - 1 - case_camp.y)


## Case réelle -> case vue par un camp (l'inverse de vers_grille).
func vers_camp(camp: int, cellule: Vector2i) -> Vector2i:
	if camp == BLEU:
		return Vector2i(cellule.x, cellule.y - (lignes - lignes_par_camp))
	return Vector2i(colonnes - 1 - cellule.x, lignes_par_camp - 1 - cellule.y)


func dans_grille(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < colonnes and c.y >= 0 and c.y < lignes


## Cette case réelle fait-elle partie de la zone de placement de ce camp ?
func dans_zone(camp: int, c: Vector2i) -> bool:
	if not dans_grille(c):
		return false
	if camp == BLEU:
		return c.y >= lignes - lignes_par_camp
	return c.y < lignes_par_camp


## Cette case vue par un camp est-elle dans sa zone de placement ?
func dans_zone_camp(case_camp: Vector2i) -> bool:
	return case_camp.x >= 0 and case_camp.x < colonnes and case_camp.y >= 0 and case_camp.y < lignes_par_camp


## Cases vues par le camp couvertes par un mur de « taille » x « taille »
## posé en case_camp (il s'étend vers la droite et vers le fond du camp).
static func cases_mur_camp(case_camp: Vector2i, taille: int) -> Array[Vector2i]:
	var cases: Array[Vector2i] = []
	for dy in taille:
		for dx in taille:
			cases.append(case_camp + Vector2i(dx, dy))
	return cases


## Les mêmes cases, en cases réelles.
func cases_mur(camp: int, case_camp: Vector2i, taille: int) -> Array[Vector2i]:
	var cases: Array[Vector2i] = []
	for c in cases_mur_camp(case_camp, taille):
		cases.append(vers_grille(camp, c))
	return cases
