class_name Formations
extends RefCounted
## Raccourcis pour créer des groupes de troupes (tests, IA, placement).


## Un groupe dont les unités sont côte à côte sur un même rang,
## à partir de « colonne » vers la droite (vu par le joueur).
static func en_ligne(donnees: Donnees, type_troupe: String, colonne: int, rang: int) -> Dictionary:
	var nombre := int(donnees.troupes[type_troupe]["unites_par_carte"])
	var cases: Array[Vector2i] = []
	for i in nombre:
		cases.append(Vector2i(colonne + i, rang))
	return {"type": type_troupe, "cases": cases}
