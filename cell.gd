extends Node2D


func _draw():
	draw_circle(Vector2(0, 0), 50, Color(0.4, 0.8, 0.5))
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
