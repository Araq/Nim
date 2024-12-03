from system import string, int, seq, `&`, `$`, `*`, `@`, echo, add, RootObj
import fixtures/mclass_macro

class Animal of RootObj:
  var name: string
  var age: int
  method vocalize: string {.base.} = "..." # use `base` pragma to annonate base methods
  method age_human_yrs: int {.base.} = self.age # `this` is injected
  proc `$`: string = "animal:" & self.name & ":" & $self.age

class Dog of Animal:
  method vocalize: string = "woof"
  method age_human_yrs: int = self.age * 7
  proc `$`: string = "dog:" & self.name & ":" & $self.age

class Cat of Animal:
  method vocalize: string = "meow"
  proc `$`: string = "cat:" & self.name & ":" & $self.age

class Rabbit of Animal:
  proc newRabbit(name: string, age: int) = # the constructor doesn't need a return type
    result = Rabbit(name: name, age: age)
  method vocalize: string = "meep"
  proc `$`: string =
    self.ag#[!]#
    result = "rabbit:" & self.name & ":" & $self.age

# ---

var animals: seq[Animal] = @[]
animals.add(Dog(name: "Sparky", age: 10))
animals.add(Cat(name: "Mitten", age: 10))

for a in animals:
  echo a.vocalize()
  echo a.age_human_yrs()

let r = newRabbit("Fluffy", 3)
echo r.vocalize()
echo r.age_human_yrs()
echo r

discard """
$nimsuggest --tester $file
>sug $1
sug;;skField;;age;;int;;$file;;6;;6;;"";;100;;Prefix
sug;;skMethod;;twithin_macro_prefix.age_human_yrs;;proc (self: Animal): int{.raises: <inferred> [].};;$file;;8;;9;;"";;100;;Prefix
"""
