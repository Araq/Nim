discard """
  targets: "cpp"
  cmd: "nim cpp -r $file"
  output: '''
1.0
1.0
'''

"""
{.emit:"""/*TYPESECTION*/
struct Point {
  float x, y, z;
  Point(float x, float y, float z): x(x), y(y), z(z) {}
  Point() = default;
};
struct Direction {
  float x, y, z;
  Direction(float x, float y, float z): x(x), y(y), z(z) {}
  Direction() = default;
};
struct Axis {
  Point origin;
  Direction direction;
  Axis(Point origin, Direction direction): origin(origin), direction(direction) {}
  Axis() = default;
};

""".}

type
  Point {.importcpp.} = object
    x, y, z: float
  
  Direction {.importcpp.} = object
    x, y, z: float

  Axis {.importcpp.} = object
    origin: Point
    direction: Direction

proc makeAxis(origin: Point, direction: Direction): Axis {. constructor, importcpp:"Axis(@)".}
proc makePoint(x, y, z: float): Point {. constructor, importcpp:"Point(@)".}
proc makeDirection(x, y, z: float): Direction {. constructor, importcpp:"Direction(@)".}

var axis1 = makeAxis(Point(x: 1.0, y: 2.0, z: 3.0), Direction(x: 4.0, y: 5.0, z: 6.0)) #Triggers the error (T1)
var axis2Ctor = makeAxis(makePoint(1.0, 2.0, 3.0), makeDirection(4.0, 5.0, 6.0)) #Do not triggers

proc main() = #Do not triggers as Tx are inside the body
  let test = makeAxis(Point(x: 1.0, y: 2.0, z: 3.0), Direction(x: 4.0, y: 5.0, z: 6.0))
  echo test.origin.x

main()

echo $axis1.origin.x  #Make sures it's init