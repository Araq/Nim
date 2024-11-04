proc valid*(): string =
  let x = 317
  "valid"

proc invalid*(): string =
  result = "foo"
  "invalid" #[tt.Error
  ^ cannot use implicit return, the `result` symbol was used in 'invalid'; got expression of type 'string']#
