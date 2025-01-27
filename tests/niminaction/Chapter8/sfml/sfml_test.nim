discard """
action: compile
disabled: "windows"
disabled: osx
"""

import sfml, os
var window = newRenderWindow(videoMode(800, 600), "SFML works!")

var event: Event
discard window.pollEvent(event)
window.clear(newColor(29, 64, 153, 255))
window.display()

sleep(1000)
