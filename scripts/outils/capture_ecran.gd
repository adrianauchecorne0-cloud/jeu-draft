extends SceneTree
## Outil pour Claude (Adrian n'en a pas besoin) : lance une scène sur un écran
## virtuel et enregistre des captures PNG à des images précises, pour vérifier
## le rendu sans téléphone ni PC. On peut aussi appeler une fonction de la scène
## à une image donnée (ex. 30:lancer_combat). Exemple (Linux) :
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##     --resolution 720x1280 --script res://scripts/outils/capture_ecran.gd \
##     -- res://scenes/bac_a_sable.tscn /tmp/captures 40,200,900 30:lancer_combat

var _scene := "res://scenes/bac_a_sable.tscn"
var _dossier := "/tmp/captures"
var _images: Array[int] = [40, 300, 900]
var _actions: Dictionary = {}
var _racine: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	if args.size() >= 2:
		_dossier = args[1]
	if args.size() >= 3:
		_images.clear()
		for morceau in args[2].split(","):
			_images.append(int(morceau))
	if args.size() >= 4:
		for morceau in args[3].split(","):
			var parties := morceau.split(":")
			_actions[int(parties[0])] = parties[1]
	DirAccess.make_dir_recursive_absolute(_dossier)
	_racine = load(_scene).instantiate()
	root.add_child(_racine)
	_capturer.call_deferred()


func _capturer() -> void:
	var derniere: int = _images.max()
	var image_courante := 0
	while image_courante <= derniere:
		await process_frame
		image_courante += 1
		if _actions.has(image_courante):
			_racine.call(_actions[image_courante])
		if image_courante in _images:
			await RenderingServer.frame_post_draw
			var chemin := "%s/image_%04d.png" % [_dossier, image_courante]
			root.get_texture().get_image().save_png(chemin)
			print("Capture : ", chemin)
	quit()
