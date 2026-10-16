class_name PortalView
extends MeshInstance3D

# A doorway you can see through. A second camera stands at the matching spot in front of the door on the
# other side and its picture is drawn over the doorway in screen space, so the view lines up with the
# player's own. `source` is the mount this quad sits on, `dest` the mount of the door it leads to
# (local +z of a mount points into its room).

const FLIP := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
const VIEW_RANGE := 10.0
const RENDER_SCALE := 0.75

static var _shader: Shader

var source: Node3D
var dest: Node3D
var viewport: SubViewport
var cam: Camera3D


func _init(size := Vector2(0.9, 2.1)) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	mesh = quad
	if _shader == null:
		_shader = Shader.new()
		_shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\n" \
				+ "uniform sampler2D view : source_color, filter_linear;\n" \
				+ "void fragment() {\n\tvec3 c = texture(view, SCREEN_UV).rgb;\n\tALBEDO = mix(c, vec3(0.75, 0.9, 1.0), 0.06);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	cam = Camera3D.new()
	viewport.add_child(cam)
	add_child(viewport)
	mat.set_shader_parameter("view", viewport.get_texture())
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	var main_cam := get_viewport().get_camera_3d()
	if source == null or dest == null or main_cam == null or not is_instance_valid(dest):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var local := source.to_local(main_cam.global_position)
	var facing := -main_cam.global_transform.basis.z.dot(source.global_transform.basis.z) > -0.35
	if not facing or local.z < -0.2 or local.length() > VIEW_RANGE:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var wanted := Vector2i((Vector2(get_viewport().get_visible_rect().size) * RENDER_SCALE).round())
	if viewport.size != wanted and wanted.x > 8 and wanted.y > 8:
		viewport.size = wanted
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cam.global_transform = dest.global_transform * FLIP * source.global_transform.affine_inverse() \
			* main_cam.global_transform
	cam.fov = main_cam.fov
	# The camera starts out behind the far door's wall; the near plane is set to the doorway so the wall
	# (and anything else between the camera and the doorway) is cut away.
	var plane_n := dest.global_transform.basis.z
	var behind := (dest.global_position - cam.global_position).dot(plane_n)
	var straight := maxf(-cam.global_transform.basis.z.dot(plane_n), 0.35)
	cam.near = clampf(behind / straight - 0.02, 0.05, 40.0)
	cam.current = true
