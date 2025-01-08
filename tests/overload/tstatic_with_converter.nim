discard """
output: '''
9.0
'''
"""

### bug #6773

{.emit: """ /*INCLUDESECTION*/
typedef double cimported;
 
cimported set1_imported(double x) {
  return x;
}
 
"""}
 
type vfloat{.importc: "cimported", nodecl.} = object
 
proc set1(a: float): vfloat {.importc: "set1_imported".}
 
converter scalar_to_vector(x: float): vfloat =
  set1(x)
 
proc sqrt(x: vfloat): vfloat =
  x
 
proc pow(x, y: vfloat): vfloat =
  y
 
proc `^`(x: vfloat, exp: static[int]): vfloat =
  when exp == 0:
    1.0
  else:
    x
 
proc `^`(x: vfloat, exp: static[float]): vfloat =
  when exp == 0.5:
    sqrt(x)
  else:
    pow(x, exp)
 
proc `$`(x: vfloat): string =
  let y = cast[ptr float](addr x)
  result = $y[]
 
let x = set1(9.0)
echo x^0.5
