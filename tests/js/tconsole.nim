discard """
  output: '''
Hello, console
1 2 3
1 'hi' 1.1'''
  disabled: "freebsd"
"""

# This file tests the JavaScript console

import jsconsole

console.log("Hello, console")
console.log(1, 2, 3)
