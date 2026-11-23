# Jeu Draft : mémo pour Claude

## Qui et comment

- Projet d'Adrian. Il n'est pas développeur : il fait le game design, Claude écrit le code. Il est graphiste : il fera les images des personnages.
- Toujours répondre en français, simplement, sans jargon. À chaque étape, dire exactement comment tester : quel bouton, quoi regarder, ce qui est normal.
- Adrian teste sur son PC Windows avec **Godot 4.7.2, version standard** (pas .NET).
- Code sur GitHub : `adrianauchecorne0-cloud/jeu-draft` (privé). Adrian récupère le code avec GitHub Desktop (« Fetch origin » puis « Pull origin »), puis F5 dans Godot. Il a aussi un vieux dépôt local `jeu-draft` non publié (« Other » dans GitHub Desktop) : ce n'est pas le bon, il ne faut pas le publier.
- **Un commit par étape qui fonctionne**, message en français. Avant de pousser : récupérer d'abord ce qu'Adrian a pu modifier (il peut changer les fichiers de `data/`).
- Claude teste lui-même avant chaque envoi, avec Godot dans son espace de travail (Adrian a donné son accord pour le téléchargement) :
  - installer : télécharger `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` dans `~/godot_bin/` et le dézipper (même version qu'Adrian) ;
  - première fois : `godot --headless --path . --import` (enregistre les classes ; un « Aborted » à la fin est sans gravité) ;
  - tests automatiques : `godot --headless --path . res://scenes/test_combat.tscn --quit-after 10` → vérifier « Résultat : x/x OK » et l'absence de `SCRIPT ERROR` ;
  - rendu visuel et combat jusqu'au bout : captures PNG avec `xvfb-run` et `scripts/outils/capture_ecran.gd` (mode d'emploi en tête du fichier ; il peut appeler `lancer_combat` à une image donnée), puis regarder les images avant d'envoyer. La console affiche « Fin du combat : ... ».
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
- Pas encore d'images : chaque troupe est une forme de couleur. Bleu = le joueur, rouge = l'adversaire. Les images viendront d'Adrian (voir « Images »).
- L'adversaire sera une IA simple qui achète et place au hasard, dans son budget.
- Interface la plus simple possible : peu de boutons (demande d'Adrian).

## Règles validées par Adrian

Toutes les valeurs ci-dessous vivent dans `data/` et se changent sans toucher au code.

### Terrain (révisé le 23 nov.)
- Grille **invisible et fine** de 27 colonnes × 42 lignes, format portrait. Adrian ne veut pas voir de grille ; elle sert seulement aux déplacements.
- Zone du joueur bleu : les 18 lignes du bas. Zone rouge : les 18 du haut. Les 6 lignes du milieu sont neutres (personne n'y pose rien).
- Une unité occupe une case (petite à l'écran). Déplacements en 4 directions (pas de diagonale).

### Troupes (révisé le 23 nov. : guerrier et colosse retirés à la demande d'Adrian)

| Troupe | Forme | Vie | Dégâts | Cadence | Portée | Vitesse | Coût | Unités par carte |
|---|---|---|---|---|---|---|---|---|
| Archer | triangle | 60 | 15 | 12 tours (1,2 s) | 12 cases (distance) | 0,6 case/tour | 3 | 2 |
| Soldat | carré | 100 | 20 | 8 tours (0,8 s) | 1 (corps à corps) | 0,8 case/tour | 3 | 3 |

Ajouter une troupe = ajouter un bloc dans `troupes.json` : elle apparaît toute seule dans le bac à sable (formes possibles : cercle, carre, triangle).

### Structure
- Mur : **cube couleur sable** (autre couleur que les camps), carré de 2 × 2 cases, coût 1, indestructible. Il bloque le passage, pas les tirs. 4 murs maximum par joueur dans la vraie partie, **illimités dans le bac à sable**.

### Groupes (pour la vraie partie, pas encore utilisés)
- Une carte = un groupe de N unités. Au placement, le groupe se déplace d'un bloc.
- En combat, chaque unité agit seule (pions indépendants).

### Combat
- Un tour = un petit pas de temps : **0,1 s à l'écran** (`regles.json`, `affichage.secondes_par_tour`). C'est l'ancienne vitesse x2 : Adrian trouvait la x1 trop lente. **Pas de bouton de vitesse.**
- Chaque tour se joue en deux phases.
  1. **Attaques** : chaque unité qui a un ennemi à portée le frappe si elle est rechargée (cadence). Elle ne bouge pas tant qu'un ennemi est à portée, même pendant la recharge. Toutes les attaques sont simultanées (dégâts appliqués à la fin de la phase), donc deux unités peuvent s'entretuer. Puis les morts sont retirées.
  2. **Déplacements** : les unités sans ennemi à portée avancent vers la position d'attaque la plus proche, en contournant murs et troupes.
- Aucun hasard dans le combat : même placement = même résultat.
- Le combat s'arrête dès qu'un camp n'a plus de troupes. Si les deux camps sont vides en même temps : manche nulle.
- Limite de 900 tours (90 s) : au-delà, gagne le camp à qui il reste le plus de points de vie au total. Égalité parfaite : manche nulle.

### Manches et partie (pour plus tard)
- Chaque manche : +10 points de budget. Magasin de 5 cartes tirées au hasard parmi les troupes (doublons possibles), chacune achetable une fois. Le mur est toujours disponible, hors tirage.
- Les points non dépensés sont gardés pour la manche suivante (choix par défaut, Adrian peut le changer).
- Les troupes mortes reviennent à pleine vie à la manche suivante. Elles gardent leur place, on peut les redéplacer et en ajouter.
- Pendant l'achat et le placement, la moitié adverse est cachée.
- Partie : le premier à 2 manches gagnées l'emporte (la 3e manche ne se joue qu'à 1-1). Manche nulle = personne ne marque. Si personne n'a 2 victoires après 3 manches : partie nulle.

## Bac à sable (écran actuel, F5)

Demandé par Adrian le 23 nov. pour tester le modèle de combat.
- La compo rouge est fixe (bloc `demo` de `data/combats_test.json`) et visible.
- Le bleu place **sans limite** : palette Archer / Soldat / Mur (un bouton par troupe de `troupes.json`, plus le mur). Toucher sa zone pose ; toucher une troupe ou un mur l'enlève ; on peut glisser le doigt pour poser ou effacer en série.
- Boutons : « Tout effacer », « Lancer le combat ». Pendant le combat : « Arrêter ». À la fin : bandeau de victoire et « Recommencer », qui revient au placement en gardant la compo bleue.
- La compo bleue de départ vient aussi du bloc `demo` (avec elle, le rouge gagne en 9,6 s : à Adrian de trouver mieux).

## Affichage « vivant » (demande d'Adrian)

- Pas de grille visible ; fonds de zones discrets (bleu en bas, rouge en haut, gris au milieu), zone bleue qui pulse en placement.
- Petites unités. **Wiggle** : balancement gauche-droite permanent, plus fort en marchant ; petit rebond en marchant ; ombre au sol.
- Corps à corps : élan vers la cible et arc de coup. Distance : flèche qui voyage. Flash blanc quand une unité est touchée, chiffre de dégâts (un par unité et par tour, qui la suit), barre de vie seulement si blessée, disparition en rétrécissant.
- **Images** : Adrian fera ses personnages en images ; l'animation sera seulement ce wiggle. Champ `image` dans `troupes.json` / `structures.json` (ex. `res://images/archer.png`) : l'image remplace la forme et garde le wiggle, avec un petit cercle de la couleur du camp. Mode d'emploi pour Adrian : `images/LISEZMOI.txt`.

## Architecture technique

- Godot 4.7, GDScript, rendu « Compatibilité » (marche partout, y compris les vieux téléphones). Écran de jeu 720 × 1280 (portrait), affiché en 405 × 720 sur PC.
- **Séparation stricte logique / affichage.**
  - `scripts/logique/` : uniquement des classes `RefCounted`, aucun nœud, aucun affichage. On doit pouvoir simuler des milliers de combats sans écran.
  - `scripts/affichage/` : lit l'état et l'historique du combat, ne décide jamais rien.
  - `scripts/tests/` : scène de vérifications automatiques. `scripts/outils/` : outils pour Claude.
- **Données** : toutes les stats et règles dans `data/*.json`, jamais en dur dans le code. Les clés qui commencent par `_` sont des commentaires pour Adrian, ignorées au chargement. Les nombres JSON arrivent en float dans Godot : toujours convertir avec `int()`.
- Classes actuelles :
  - `Donnees` (`donnees.gd`) : charge `data/`, vérifie les champs (`problemes()`), lit n'importe quel JSON de `data/` (`lire_fichier()`), `regle_entiere()`, `regle_decimale()`.
  - `Terrain` (`terrain.gd`) : dimensions, zones, conversions case vue par un camp ↔ case réelle (`vers_grille`, `vers_camp`), cases couvertes par un mur.
  - `Unite` (`unite.gd`) : une unité en combat (vie, dégâts, cadence/recharge, portée, vitesse).
  - `Combat` (`combat.gd`) : le moteur. `Combat.new(donnees, armee_bleue, armee_rouge, enregistrer = true, limiter_murs = true)`, puis `simuler()` ou `jouer_tour()`. Garde un `historique` d'événements par tour (`attaque`, `mort`, `deplacement`) ; `blocs_murs` pour l'affichage ; `enregistrer = false` pour les simulations en masse.
  - `Formations` (`formations.gd`) : raccourcis pour créer des groupes (en ligne).
  - `VueTerrain` (`affichage/vue_terrain.gd`) : dessin et animations. `preparer(combat)` juste après `Combat.new()`, puis `appliquer_tour(evenements)` à chaque tour. En placement : `mode_placement`, `type_apercu` (fantôme sous la souris), signal `case_touchee(cellule, debut)`.
  - `bac_a_sable.gd` (scène `scenes/bac_a_sable.tscn`) : l'écran actuel. Pendant le placement, l'aperçu est un `Combat` créé mais pas lancé (il valide les cases).
- **Combats de test** : `data/combats_test.json`, bloc `demo` (bleu / rouge au format armée ci-dessous).
- **Format d'une armée** (sérialisable, pour enregistrer des compositions plus tard) :
  `{"groupes": [{"type": "soldat", "cases": [case, ...]}], "murs": [case, ...]}`.
  Une case est vue **du point de vue du joueur** : `(colonne, rang)`, colonne 0 = sa gauche, rang 0 = sa ligne la plus proche du centre, rang 17 = son fond. Accepte `Vector2i` ou `[x, y]`. Un mur se donne par son coin et s'étend vers la droite et le fond du camp. Le camp rouge est tourné de 180°, donc la même armée peut jouer en bleu ou en rouge.
- **Grille réelle** : `(x, y)`, `(0, 0)` en haut à gauche. Bleu en bas (y de 24 à 41), rouge en haut (y de 0 à 17).
- **Détails du combat** (garder ces règles pour que les résultats restent reproductibles) :
  - Portée : un ennemi est à portée si dx² + dy² ≤ (portée + 0,5)². Portée 1 inclut les diagonales.
  - Cible : l'ennemi à portée le plus proche, puis le moins de vie, puis le plus petit id.
  - Cadence : la recharge baisse de 1 à chaque tour ; on frappe quand elle est à 0, puis elle repart à « cadence ». Prête dès le début.
  - Ordre des déplacements : alterné bleu / rouge, le camp qui commence change à chaque tour (bleu aux tours impairs). Dans un camp : le plus avancé d'abord, puis de gauche à droite (vu par ce camp).
  - Chemin : un champ de distances par (camp, portée), recalculé à chaque tour, à partir des cases d'où l'on peut frapper un ennemi (les murs bloquent, pas les troupes). L'unité va vers une case voisine libre plus proche (préférence vue par le camp : avancer, gauche, droite, reculer). Si des troupes bloquent, recherche en largeur qui les contourne (600 cases max) ; sinon elle attend.
  - Vitesse : réserve de mouvement +vitesse par tour (plafonnée), une case par point. Une unité s'arrête dès qu'un ennemi est à portée.
- Performances mesurées : combat de démo (19 unités) ≈ 2 ms par tour ; bataille de 120 unités ≈ 5 ms en moyenne, 50 ms au pire. À optimiser avant le simulateur d'équilibrage.
- À vérifier au simulateur : deux armées identiques en miroir (120 unités) ont donné une victoire rouge. L'ordre de jeu donne peut-être un petit avantage ; à mesurer.

## Conventions

- Noms dans le code en français, sans accents (`unite`, `degats`, `portee`).
- La scène lancée par F5 (`run/main_scene` dans `project.godot`) pointe sur ce qu'on teste à l'étape en cours.
- Scènes `.tscn` écrites à la main avec des chemins `res://` ; fichiers `.uid` ignorés par Git.
- Pas de caractères spéciaux (flèches, coches, symboles) dans les textes affichés : la police par défaut de Godot ne les a pas forcément. Les icônes des boutons sont dessinées par le code.
- Avant un export Android/iOS : ajouter `data/*.json` dans « Filtres pour exporter les fichiers non-ressources » du préréglage d'export.

## Étapes

| # | Étape | Comment Adrian teste | Statut |
|---|---|---|---|
| 0 | Projet Godot vide en portrait | Le projet s'ouvre sans erreur | **validé par Adrian** (23 nov.) |
| 1 | Combat automatique sans affichage + fichiers de stats | Ouvrir `scenes/test_combat.tscn` puis F6 : « Résultat : 22/22 OK » puis le résumé du combat de démo | **validé par Adrian** (23 nov.) |
| 2 | Afficher le combat | — | **validé par Adrian** (23 nov.), avec ses retours : plus de grille visible, unités plus petites, plus rapide, plus vivant, moins de boutons |
| 3 | Bac à sable : grille fine invisible, Archer / Soldat / Mur, placement illimité, combat vivant | F5 : placer, effacer, glisser, lancer ; le combat s'arrête quand un camp est vide ; Recommencer garde le placement | validé par Claude (captures + touchers simulés), à voir chez Adrian |
| 4 | Placement de la vraie partie (groupes d'un bloc, zone adverse cachée) | Placer puis lancer | à faire |
| 5 | Magasin, budget, IA qui achète et place au hasard | Jouer une manche complète | à faire |
| 6 | Partie en 3 manches (troupes gardées, points reportés, score, Rejouer) | Jouer une partie entière | à faire |
| 7 | Simulateur d'équilibrage : 1 000 combats IA contre IA sans affichage | Tableau des taux de victoire par troupe | à faire |
| 8 | Images des personnages d'Adrian (le wiggle est déjà prêt) | Mettre une image dans `images/`, l'indiquer dans `troupes.json` | possible dès maintenant |
