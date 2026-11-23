class_name Unite
extends RefCounted
## Une unité sur le terrain pendant un combat. Logique pure : aucun affichage.

var id: int
var camp: int
var type_troupe: String
var nom: String
var forme: String
var vie_max: int
var vie: int
var degats: int
var portee: int
## Portée au carré, avec une marge d'une demi-case : un ennemi est à portée
## si dx² + dy² <= portee_carre. Portée 1 inclut donc les diagonales.
var portee_carre: float
var vitesse: float
## Case réelle sur la grille : (colonne, ligne), (0, 0) en haut à gauche.
var cellule: Vector2i
## Réserve de mouvement : +vitesse à chaque tour, une case dès qu'elle atteint 1.
var reserve_mouvement: float = 0.0


func _init(p_id: int, p_camp: int, p_type: String, stats: Dictionary, p_cellule: Vector2i) -> void:
	id = p_id
	camp = p_camp
	type_troupe = p_type
	nom = str(stats.get("nom", p_type))
	forme = str(stats.get("forme", "cercle"))
	vie_max = maxi(1, int(stats.get("vie", 1)))
	vie = vie_max
	degats = int(stats.get("degats", 0))
	portee = maxi(1, int(stats.get("portee", 1)))
	portee_carre = (portee + 0.5) * (portee + 0.5)
	vitesse = float(stats.get("vitesse", 1.0))
	cellule = p_cellule


func est_vivante() -> bool:
	return vie > 0


## Peut-elle frapper une unité placée sur cette case ?
func a_portee_de(case_cible: Vector2i) -> bool:
	var dx := case_cible.x - cellule.x
	var dy := case_cible.y - cellule.y
	return dx * dx + dy * dy <= portee_carre
