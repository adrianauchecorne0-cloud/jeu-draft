# Jeu Draft : mémo pour Claude

## Qui et comment

- Projet d'Adrian. Il n'est pas développeur : il fait le game design, Claude écrit le code.
- Toujours répondre en français, simplement, sans jargon. À chaque étape, dire exactement comment tester : quel bouton, quoi regarder, ce qui est normal.
- Adrian teste sur son PC Windows avec **Godot 4.7, version standard** (pas .NET).
- Code sur GitHub : `adrianauchecorne0-cloud/jeu-draft` (privé). Adrian récupère le code avec GitHub Desktop (« Fetch origin » puis « Pull origin »), puis F5 dans Godot.
- **Un commit par étape qui fonctionne**, message en français. Avant de pousser : récupérer d'abord ce qu'Adrian a pu modifier (il peut changer les fichiers de `data/`).
- Claude teste lui-même avant chaque envoi, avec Godot sans écran (Adrian a donné son accord pour le téléchargement) :
  - installer : télécharger `https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip` dans `~/godot_bin/` et le dézipper ;
  - première fois : `godot --headless --path . --import` (enregistre les classes) ;
  - lancer la scène F5 : `godot --headless --path . --quit-after 10`, puis vérifier « Résultat : x/x OK » et l'absence de `SCRIPT ERROR`.
  - Adrian valide ensuite chez lui ce qui est visuel.

## La vision

Jeu mobile de stratégie en format portrait : du draft et de l'auto-combat, inspiré de Draft Showdown (Voodoo) et de Clash Royale, avec les règles et le design d'Adrian.

Une partie oppose deux joueurs en plusieurs manches. Chaque manche se déroule en trois temps :
1. **Achat** : un budget de points et des cartes tirées au hasard. Chaque carte donne un groupe de troupes.
2. **Placement** : on pose ses groupes sur sa moitié du terrain et on peut les avancer ou les reculer. On peut aussi poser des murs pour forcer les troupes ennemies à faire des détours.
3. **Combat** : automatique, tour par tour.

On ne voit jamais la composition adverse avant le combat. D'une manche à l'autre, on garde ses troupes et on améliore sa composition avec un nouveau budget.

Plus tard (pas maintenant) : progression, packs, arènes à la Clash Royale, compositions enregistrées par d'autres joueurs utilisées comme adversaires, équilibrage sur des milliers de parties simulées.

## Périmètre actuel : le système de jeu uniquement

- Pas de menu, pas d'écran d'accueil, pas de multijoueur, pas de progression ni de packs.
- Pas de visuels : chaque troupe est une forme de couleur (cercle, carré, triangle). Bleu = le joueur, rouge = l'adversaire.
- L'adversaire est une IA simple qui achète et place au hasard, dans son budget.
- 3 types de troupes et 1 structure, pas plus pour l'instant.

## Règles validées par Adrian (23 nov. 2026)

Toutes les valeurs ci-dessous vivent dans `data/` et se changent sans toucher au code.

### Terrain
- Grille de 9 colonnes × 14 lignes, format portrait.
- Zone du joueur bleu : les 6 lignes du bas. Zone rouge : les 6 du haut. Les 2 lignes du milieu sont neutres (personne n'y pose rien).
- Une unité occupe une case. Déplacements en 4 directions (pas de diagonale).

### Troupes (valeurs de départ)

| Troupe | Forme | Coût | Unités par carte | Vie | Dégâts par tour | Portée | Vitesse |
|---|---|---|---|---|---|---|---|
| Guerrier | cercle | 3 | 3 | 100 | 20 | 1 | 1 case par tour |
| Archer | triangle | 3 | 2 | 60 | 15 | 4 | 1 case par tour |
| Colosse | carré | 4 | 1 | 400 | 50 | 1 | 0,5 (1 case tous les 2 tours) |

Intention : pierre-feuille-ciseaux. Le colosse bat les guerriers, les guerriers battent les archers, les archers battent le colosse.

### Structure
- Mur : coût 1, occupe une case, indestructible. Il bloque le passage, pas les tirs. 4 murs maximum par joueur, posés dans sa propre zone.

### Groupes
- Une carte = un groupe de N unités. Au placement, le groupe se déplace d'un bloc.
- En combat, chaque unité agit seule (pions indépendants).

### Combat
- Chaque tour se joue en deux phases.
  1. **Attaques** : chaque unité qui a un ennemi à portée le frappe. Toutes les attaques sont simultanées (dégâts appliqués à la fin de la phase), donc deux unités peuvent s'entretuer. Puis les morts sont retirées.
  2. **Déplacements** : les unités qui n'ont pas frappé avancent vers la position d'attaque la plus proche, en contournant murs et troupes.
- Aucun hasard dans le combat : même placement = même résultat.
- Une manche est gagnée quand l'adversaire n'a plus de troupes. Si les deux camps sont vides en même temps : manche nulle.
- Limite de 50 tours : au-delà, gagne le camp à qui il reste le plus de points de vie au total. Égalité parfaite : manche nulle.

### Manches et partie
- Chaque manche : +10 points de budget. Magasin de 5 cartes tirées au hasard parmi les 3 troupes (doublons possibles), chacune achetable une fois. Le mur est toujours disponible, hors tirage.
- Les points non dépensés sont gardés pour la manche suivante (choix par défaut, Adrian peut le changer).
- Les troupes mortes reviennent à pleine vie à la manche suivante. Elles gardent leur place, on peut les redéplacer et en ajouter.
- Pendant l'achat et le placement, la moitié adverse est cachée.
- Partie : le premier à 2 manches gagnées l'emporte (la 3e manche ne se joue qu'à 1-1). Manche nulle = personne ne marque. Si personne n'a 2 victoires après 3 manches : partie nulle.

## Architecture technique

- Godot 4.7, GDScript, rendu « Compatibilité » (marche partout, y compris les vieux téléphones). Écran de jeu 720 × 1280 (portrait), affiché en 405 × 720 sur PC.
- **Séparation stricte logique / affichage.**
  - `scripts/logique/` : uniquement des classes `RefCounted`, aucun nœud, aucun affichage. On doit pouvoir simuler des milliers de combats sans écran.
  - `scripts/affichage/` (à partir de l'étape 2) : lit l'état et l'historique du combat, ne décide jamais rien.
- **Données** : toutes les stats et règles dans `data/*.json`, jamais en dur dans le code. Les clés qui commencent par `_` sont des commentaires pour Adrian, ignorées au chargement. Les nombres JSON arrivent en float dans Godot : toujours convertir avec `int()`.
- Classes actuelles :
  - `Donnees` (`donnees.gd`) : charge `data/`, vérifie les champs (`problemes()`).
  - `Unite` (`unite.gd`) : une unité en combat.
  - `Combat` (`combat.gd`) : le moteur. `Combat.new(donnees, armee_bleue, armee_rouge)`, puis `simuler()` ou `jouer_tour()` pas à pas. Garde un `historique` d'événements par tour (`attaque`, `mort`, `deplacement`) pour l'affichage ; `enregistrer = false` pour les simulations en masse.
  - `Formations` (`formations.gd`) : raccourcis pour créer des groupes (en ligne).
- **Format d'une armée** (sérialisable, pour enregistrer des compositions plus tard) :
  `{"groupes": [{"type": "guerrier", "cases": [case, ...]}], "murs": [case, ...]}`.
  Une case est vue **du point de vue du joueur** : `(colonne, rang)`, colonne 0 = sa gauche, rang 0 = sa ligne la plus proche du centre, rang 5 = son fond. Accepte `Vector2i` ou `[x, y]`. Le camp rouge est tourné de 180°, donc la même armée peut jouer en bleu ou en rouge.
- **Grille réelle** : `(x, y)`, `(0, 0)` en haut à gauche. Bleu en bas (y de 8 à 13), rouge en haut (y de 0 à 5).
- **Détails du combat** (garder ces règles pour que les résultats restent reproductibles) :
  - Portée : un ennemi est à portée si dx² + dy² ≤ (portée + 0,5)². Portée 1 inclut les diagonales.
  - Cible : l'ennemi à portée le plus proche, puis le moins de vie, puis le plus petit id.
  - Ordre des déplacements : alterné bleu / rouge, le camp qui commence change à chaque tour (bleu aux tours impairs). Dans un camp : le plus avancé d'abord, puis de gauche à droite (vu par ce camp).
  - Chemin : recherche en largeur vers la case libre la plus proche d'où l'unité peut frapper. Préférence de direction (vue par le camp) : avancer, gauche, droite, reculer. Si tout est bouché par des troupes, on vise à travers elles et on n'avance que si la case suivante est libre.
  - Vitesse : réserve de mouvement +vitesse par tour (plafonnée), une case par point. Une unité s'arrête dès qu'un ennemi est à portée.

## Conventions

- Noms dans le code en français, sans accents (`unite`, `degats`, `portee`).
- La scène lancée par F5 (`run/main_scene` dans `project.godot`) pointe sur ce qu'on teste à l'étape en cours.
- Scènes `.tscn` écrites à la main avec des chemins `res://` ; fichiers `.uid` ignorés par Git.
- Pas de caractères spéciaux (flèches, coches) dans les textes affichés : la police par défaut de Godot ne les a pas forcément.
- Avant un export Android/iOS : ajouter `data/*.json` dans « Filtres pour exporter les fichiers non-ressources » du préréglage d'export.

## Étapes

| # | Étape | Comment Adrian teste | Statut |
|---|---|---|---|
| 0 | Projet Godot vide en portrait | Le projet s'ouvre sans erreur (scène `scenes/principal.tscn`, F6 pour la voir seule) | validé par Claude (Godot sans écran), à voir chez Adrian |
| 1 | Combat automatique sans affichage + fichiers de stats | F5 : « Résultat : 16/16 OK » puis le journal du combat (victoire bleue en 20 tours), à l'écran et dans « Sortie ». Un avertissement jaune « Mur refusé » est normal (test des 4 murs max) | validé par Claude (Godot sans écran), à voir chez Adrian |
| 2 | Afficher le combat (grille, formes, barres de vie, pause, accélérer) | Regarder le même combat qu'à l'étape 1 | à faire |
| 3 | Murs et détours, visibles | Un combat de test avec murs : les ennemis contournent | à faire |
| 4 | Placement à la main (poser, glisser, zone adverse cachée, bouton Combat) | Placer puis lancer | à faire |
| 5 | Magasin, budget, IA qui achète et place au hasard | Jouer une manche complète | à faire |
| 6 | Partie en 3 manches (troupes gardées, points reportés, score, Rejouer) | Jouer une partie entière | à faire |
| 7 | Simulateur d'équilibrage : 1 000 combats IA contre IA sans affichage | Tableau des taux de victoire par troupe | à faire |
