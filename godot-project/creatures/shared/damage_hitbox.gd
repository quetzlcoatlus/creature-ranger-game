extends Area2D
# Active only during a creature's attack animation (toggled by the creature script).
# If the drawing line intersects this shape while monitoring is true, the player takes damage
# and the line breaks. DrawingSystem reads it geometrically each frame.
