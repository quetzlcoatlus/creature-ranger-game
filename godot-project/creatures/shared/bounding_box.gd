extends Area2D
# A larger shape used as the reference point for loop-enclosure detection.
# DrawingSystem tests whether this area's center (global_position) is inside the drawn polygon.
# Keeping this as a separate node allows the enclosure threshold to be tuned independently
# from the capture hitbox size.
