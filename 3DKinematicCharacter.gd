extends KinematicBody

class_name KinematicCharacter3D

export(float) var gravity = -13.0
export(float) var max_speed = 3.0
export(float) var max_crouch_speed = 1.0
export(float) var acceleration = 30.0
export(float) var deacceleration = 10.0
export(float, 0, 100) var inertia = 5.0
export(float) var jump_force = 5.0
export(float, 0.0, 1.0, 0.05) var air_control = 0.8

const _floor_angle_threshold = 0.01
const CMP_EPSILON = 0.00001

export(float, 0.0, 10.0) var _step_offset = 0.3 # 0.4
export(float) var _floor_max_angle: float = deg2rad(80.0) # Lower values than 80 will allow steps with slightly angled ceilings 

# Variables
var bullet_backend = ProjectSettings.get("physics/3d/physics_engine") in ["DEFAULT", "Bullet"]
var _current_max_speed: float = max_speed
var _velocity: Vector3 = Vector3()

var _infinite_intertia: bool = false
var _stop_on_slope: bool = true
var _on_floor: bool = false
var _floor_angle: float = 0.0
var _snap_vector = Vector3.DOWN
var _floor_normal = Vector3.ZERO
var _on_ceiling = false
var _on_wall = false
var _floor_velocity = Vector3()
var _on_floor_body = RID()
var _collisions = []

enum CONTROLLER_STATE {
	SLIDING,
	STEPPING_UP,
	FALLING,
}

var CONTROLLER_STATE_NAMES = {
	CONTROLLER_STATE.SLIDING: "SLIDING",
	CONTROLLER_STATE.STEPPING_UP: "STEPPING UP",
	CONTROLLER_STATE.FALLING: "FALLING"
}

var _controller_state = null
var _controller_state_name = null

# debug state
var visual_vector1 = Vector3.ZERO
var visual_vector2 = Vector3.ZERO
var step_debug = ''

func custom_move(move_direction: Vector3, pressing_jump: bool, delta: float) -> void:
	if _on_floor:
		_snap_vector = Vector3.DOWN * delta
#		# Workaround for sliding down after jump on slope
#		if _velocity.y < 0:
#			_velocity.y = 0
#		# remove remaining up force
#		if _velocity.dot(move_direction) == 0:
#			if _velocity.y > 0:
#				_velocity.y = 0
#		
		if pressing_jump:
			_velocity.y = jump_force
			_snap_vector = Vector3.ZERO
	else:
		_velocity.y += gravity * delta
	
	move_direction.y = 0.0
	move_direction = move_direction.normalized()
	
	# Where would the player go
	var _temp_vel: Vector3 = _velocity
	var _temp_accel: float
	var _target: Vector3 = move_direction * _current_max_speed
	
	_temp_vel.y = 0.0
	if move_direction.dot(_temp_vel) > 0:
		_temp_accel = acceleration
	else:
		_temp_accel = deacceleration
	
	if not _on_floor:
		_temp_accel *= air_control
	
	# Interpolation
	_temp_vel = _temp_vel.linear_interpolate(_target, _temp_accel * delta)

	_velocity.x = _temp_vel.x
	_velocity.z = _temp_vel.z
	
	_collisions = []
	var original_pose = get_global_transform()
	
	# test move along ground
	step_move(delta)
#	print(_on_floor, " / ", step_debug)
	
	# Prop pushing
	for index in range(_collisions.size()):
		var collision = _collisions[index]
		if collision.collider.is_in_group("prop") and collision.collider is RigidBody:
			#var speed_difference = _velocity - collision.collider.linear_velocity
			var force = -collision.collision_normal * _velocity.length()
			collision.collider.apply_central_impulse(force)
	
	_controller_state_name = CONTROLLER_STATE_NAMES[_controller_state]

class KinematicState:
	var movement: Vector3
	var transform: Transform
	var on_floor: bool
	var on_ceiling: bool
	var on_wall: bool
	var floor_normal: Vector3
	var floor_velocity: Vector3
	var on_floor_body: Object
	var colliders: Array
	
	func _init(p_movement, p_transform, p_on_floor, p_on_ceiling, p_on_wall, p_floor_normal, p_floor_velocity, p_on_floor_body):
		self.movement = p_movement
		self.transform = p_transform
		self.on_floor = p_on_floor
		self.on_ceiling = p_on_ceiling
		self.on_wall = p_on_wall
		self.floor_normal = p_floor_normal
		self.floor_velocity = p_floor_velocity
		self.on_floor_body = p_on_floor_body
		self.colliders = []
	
	func set_kinematic_state(p_normal: Vector3, p_up_direction: Vector3, p_collider: Object, p_collider_velocity: Vector3, p_floor_max_angle: float):
		if p_up_direction == Vector3():
			# all is a wall
			self.on_wall = true
		else:
			var floor_angle = acos(p_normal.dot(p_up_direction))
			var ceiling_angle = acos(p_normal.dot(-p_up_direction))
			if floor_angle <= p_floor_max_angle + _floor_angle_threshold: # floor
				self.on_floor = true
				self.floor_normal = p_normal
				self.on_floor_body = p_collider
				self.floor_velocity = p_collider_velocity
			elif ceiling_angle <= p_floor_max_angle + _floor_angle_threshold: # ceiling
				self.on_ceiling = true
			else:
				self.on_wall = true

func step_move(delta):
	var original_pose = get_global_transform()
	var apply_step = true
	
	# test move along ground
	var ground_state = KinematicState.new(_velocity, original_pose, _on_floor, _on_ceiling, _on_wall, _floor_normal, _floor_velocity, _on_floor_body)
	var ground_slide = move_and_slide_internal(delta, ground_state, Vector3.UP, _stop_on_slope, 4, _floor_max_angle, _infinite_intertia, _snap_vector)
	
	# test move along step height
	var gt = original_pose
	var up_vector = Vector3.UP * _step_offset
	#visual_vector2 = up_vector
	gt.origin += up_vector
	# DETAIL: If the step height penetrates geometry the move_and_slide_internal test might recover incorrectly further than the ground slide 
	# Do penetration recovery before this second test due to step offset
	var penetrating = PhysicsServer.body_test_motion(
		get_rid(), 
		gt, 
		Vector3.ZERO, 
		false, 
		null, 
		true, 
		[])
	if penetrating:
		apply_step = false
	
	var stair_state = KinematicState.new(_velocity, gt, _on_floor, _on_ceiling, _on_wall, _floor_normal, _floor_velocity, _on_floor_body)
	var stair_slide = move_and_slide_internal(delta, stair_state, Vector3.UP, _stop_on_slope, 4, _floor_max_angle, _infinite_intertia, _snap_vector)
	
	var debug_shape = get_node_or_null("debug_shape")
	var debug_shape2 = get_node_or_null("debug_shape2")
	if debug_shape and debug_shape2:
		debug_shape.global_transform.origin = stair_slide.transform.origin
		debug_shape2.global_transform.origin = gt.origin #ground_slide.transform.origin
	
	# Prevent stepping while colliding with ceiling
	# Ceiling Test 1: Stair slide
	if stair_slide.on_ceiling:
		apply_step = false
	
	# Prevent stepping on slopes
	if ground_slide.on_floor and rad2deg(slope_angle(ground_slide.floor_normal, Vector3.UP)) > 5.0:
		apply_step = false
	
	# Prevent overstep: Cast down stair height from stair move end position for step down behaviour
	var step_down_transform = stair_slide.transform
	step_down_transform.origin += _velocity.normalized() * 0.1 # * delta
	var down_state = KinematicState.new(Vector3.DOWN * _step_offset, step_down_transform, _on_floor, _on_ceiling, _on_wall, _floor_normal, _floor_velocity, _on_floor_body)
	var down_slide = move_and_slide_internal(1.0, down_state, Vector3.UP, _stop_on_slope, 4, _floor_max_angle, _infinite_intertia, _snap_vector)
	
	if down_slide.colliders.size() > 0:
		if down_slide.on_floor: # floor
			stair_slide.transform.origin.y = down_slide.transform.origin.y
		elif down_slide.on_ceiling:
			apply_step = false
		else:
			apply_step = false
	else:
		apply_step = false
	
	var stair_pos = stair_slide.transform.origin
	var ground_pos = ground_slide.transform.origin
	# measure horizontal move lengths (disregard height)
	var ground_dist = (ground_pos.x - original_pose.origin.x) * (ground_pos.x - original_pose.origin.x) + (ground_pos.z - original_pose.origin.z) * (ground_pos.z - original_pose.origin.z)
	var stair_dist = (stair_pos.x - original_pose.origin.x) * (stair_pos.x - original_pose.origin.x) + (stair_pos.z - original_pose.origin.z) * (stair_pos.z - original_pose.origin.z)
	if (ground_dist > stair_dist or is_equal_approx(ground_dist, stair_dist)) or not apply_step: # ground move longer
		set_global_transform(ground_slide.transform)
		_velocity = ground_slide.movement
		_floor_normal = ground_slide.floor_normal
		_on_floor = ground_slide.on_floor
		_on_ceiling = ground_slide.on_ceiling
		_on_wall = ground_slide.on_wall
		_floor_velocity = ground_slide.floor_velocity
		_collisions = ground_slide.colliders
		
		_controller_state = CONTROLLER_STATE.SLIDING
		step_debug = "GROUND MOVE"
	else: # step move longer
		# Push onto step a tiny amount
		set_global_transform(stair_slide.transform)
		_velocity = stair_slide.movement
		_floor_normal = stair_slide.floor_normal
		_on_floor = stair_slide.on_floor
		_on_ceiling = stair_slide.on_ceiling
		_on_wall = stair_slide.on_wall
		_floor_velocity = stair_slide.floor_velocity
		_collisions = stair_slide.colliders
		
		_controller_state = CONTROLLER_STATE.STEPPING_UP
		step_debug = "STEP MOVE"

func move_and_slide_internal(
		p_delta: float, 
		p_kinematic_state: KinematicState, 
		p_up_direction: Vector3, 
		p_stop_on_slope: bool, 
		p_iters: int, 
		p_floor_max_angle: float, 
		p_infinite_inertia: bool,
		p_snap:  Vector3 = Vector3(0,-0.5,0)) -> KinematicState: #SNAP IS THE ISSUE WITH MY CHECK DOWN CODE!
	var slide: KinematicState = p_kinematic_state
	var body_velocity: Vector3 = slide.movement
	var body_velocity_normal: Vector3 = body_velocity.normalized()
	var body_transform: Transform = slide.transform
	var up_direction: Vector3 = p_up_direction.normalized()
	var was_on_floor: bool = slide.on_floor

	slide.colliders = []
	slide.on_floor = false
	slide.on_ceiling = false
	slide.on_wall = false
	slide.floor_normal = Vector3.ZERO
	slide.floor_velocity = Vector3.ZERO

	slide.on_floor_body = null
	var motion: Vector3 = body_velocity * p_delta
	var sliding_enabled = !p_stop_on_slope
	# No sliding on first attempt to keep floor motion stable when possible,
	# when stop on slope is enabled.
	var si = 0
	for iteration in range(p_iters):
		# IMPORTANT NOTE: In GDSCRIPT they use 32-bit floats for Vectors and debug mode
		# only shows like 4 decimal places. Ergo: Vectors look like zero but ARENT
		# So writing motion == Vector3.ZERO is BAD!
		
		var collision: PhysicsTestMotionResult = PhysicsTestMotionResult.new() 
		var found_collision: bool = false
		
		var collided: bool = PhysicsServer.body_test_motion(get_rid(), body_transform, motion, p_infinite_inertia, collision, true, [])
		var collision_motion = collision.motion
		var collision_remainder = collision.motion_remainder
		
		body_transform.origin += collision_motion
		
		if collided:
			found_collision = true
			slide.colliders.push_back(collision)
			slide.set_kinematic_state(collision.collision_normal, p_up_direction, collision.collider, collision.collider_velocity, p_floor_max_angle)
			
			if sliding_enabled or not slide.on_floor: # Sliding
				motion = collision_remainder.slide(collision.collision_normal)
				body_velocity = body_velocity.slide(collision.collision_normal)
			else:
				motion = collision_remainder
			
			# Stop on slope check
			if slide.on_floor and p_stop_on_slope:
				if (body_velocity_normal + up_direction).length() < 0.01:
					if collision_motion.length() > get_safe_margin():
						body_transform.origin -= collision_motion.slide(up_direction)
					else:
						body_transform.origin -= collision_motion
					body_velocity = Vector3.ZERO
					break
		else:
			motion = Vector3.ZERO # clear because no collision happened and motion completed
		
		sliding_enabled = true
		si += 1
		
		if !found_collision: # no collision, dont slide again 
			break
	
	if (was_on_floor and p_snap != Vector3() and !slide.on_floor):
		# Apply snap.
		var gt = body_transform
		var travel = Vector3.ZERO

		var collision: PhysicsTestMotionResult = PhysicsTestMotionResult.new()
		var collided: bool = PhysicsServer.body_test_motion(get_rid(), global_transform, p_snap, p_infinite_inertia, collision, true, [])
		
		if collided:
			var apply = true
			if up_direction != Vector3():
				if acos(collision.collision_normal.dot(up_direction)) <= p_floor_max_angle + _floor_angle_threshold:
					slide.on_floor = true
					slide.floor_normal = collision.collision_normal
					slide.on_floor_body = collision.collider
					slide.floor_velocity = collision.collider_velocity
					if p_stop_on_slope:
						# move and collide may stray the object a bit because of pre un-stucking,
						# so only ensure that motion happens on floor direction in this case.
						if (collision.motion_remainder.length() > get_safe_margin()):
							travel = collision.motion.project(up_direction)
						else:
							travel = Vector3.ZERO
				else:
					apply = false # snapped with floor direction, but did not snap to a floor, do not snap
			if apply:
				gt.origin += travel
				body_transform = gt
	
	slide.movement = body_velocity
	slide.transform = body_transform
	return slide

func sweep_test_motion(p_transform, p_motion, p_iters) -> bool:
	# prevent tunnelling with a more expensive sweep test
	var current_orientation = p_transform
	var motion_dir = p_motion / p_iters
	for i in range(p_iters):
		var clearance_result = PhysicsTestMotionResult.new()
		var clearance_colliding = PhysicsServer.body_test_motion(get_rid(), current_orientation, motion_dir, _infinite_intertia, clearance_result, true, [])
		if clearance_colliding:
			return true
		else:
			current_orientation.origin += clearance_result.motion
	return false

static func slope_angle(p_normal, p_up) -> float:
	var slope_angle: float = acos(p_normal.dot(p_up))
	return slope_angle

static func equal_floats(a, b, epsilon = CMP_EPSILON):
	return abs(a - b) <= epsilon
