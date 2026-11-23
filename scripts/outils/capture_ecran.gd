extends SceneTree
## Outil pour Claude (Adrian n'en a pas besoin) : lance une scène sur un écran
## virtuel et enregistre des captures PNG à des images précises, pour vérifier
## le rendu sans téléphone ni PC. Exemple (Linux) :
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##     --resolution 720x1280 --script res://scripts/outils/capture_ecran.gd \
##     -- res://scenes/ecran_combat.tscn /tmp/captures 40,166,460,1000

var _scene := "res://scenes/ecran_combat.tscn"
var _dossier := "/tmp/captures"
var _images: Array[int] = [40, 166, 460, 1000]


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
	DirAccess.make_dir_recursive_absolute(_dossier)
	root.add_child(load(_scene).instantiate())
	_capturer.call_deferred()


func _capturer() -> void:
	var derniere: int = _images.max()
	var image_courante := 0
	while image_courante <= derniere:
		await process_frame
		image_courante += 1
		if image_courante in _images:
			await RenderingServer.frame_post_draw
			var chemin := "%s/image_%04d.png" % [_dossier, image_courante]
			root.get_texture().get_image().save_png(chemin)
			print("Capture : ", chemin)
	quit()
