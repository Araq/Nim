# issue #5395

const a = (var b = 3; b)
echo b #[tt.Error
     ^ undeclared identifier: 'b']#
