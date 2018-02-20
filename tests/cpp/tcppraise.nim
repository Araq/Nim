discard """
  targets: "cpp"
  output: '''foo
bar
Need odd and >= 3 digits##
baz'''
"""

# bug #1888
echo "foo"
try:
  echo "bar"
  raise newException(ValueError, "Need odd and >= 3 digits")
#  echo "baz"
except ValueError:
  echo getCurrentExceptionMsg(), "##"
echo "baz"


# bug 7232
try:
 discard
except KeyError, ValueError:
  echo "except handler" # should not be invoked


#bug 7239
try:
  try:
    raise newException(ValueError, "asdf")
  except KeyError, ValueError:
    echo "except handler" # should not be invoked
    raise
except:
  echo "caught"

