
extends Node2D

func _ready() -> void:
	print("Game started")

func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_A):
		print("A key is being held")

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		print("Mouse button is being held")
