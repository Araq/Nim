#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Statistical analysis framework for performing
## basic statistical analysis of data.
## The data is analysed in a single pass, when it
## is pushed to a `RunningStat` or `RunningRegress` object.
##
## `RunningStat` calculates for a single data set
## - n (data count)
## - min (smallest value)
## - max (largest value)
## - sum
## - mean
## - variance
## - varianceS (sample variance)
## - standardDeviation
## - standardDeviationS (sample standard deviation)
## - skewness (the third statistical moment)
## - kurtosis (the fourth statistical moment)
##
## `RunningRegress` calculates for two sets of data
## - n (data count)
## - slope
## - intercept
## - correlation
##
## Procs are provided to calculate statistics on `openArray`s.
##
## However, if more than a single statistical calculation is required, it is more
## efficient to push the data once to a `RunningStat` object and then
## call the numerous statistical procs for the `RunningStat` object:

runnableExamples:
  from std/math import almostEqual

  template `~=`(a, b: float): bool = almostEqual(a, b)

  var statistics: RunningStat  # must be var
  statistics.push(@[1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0])
  doAssert statistics.n == 8
  doAssert statistics.mean() ~= 2.0
  doAssert statistics.variance() ~= 1.5
  doAssert statistics.varianceS() ~= 1.714285714285715
  doAssert statistics.skewness() ~= 0.8164965809277261
  doAssert statistics.skewnessS() ~= 1.018350154434631
  doAssert statistics.kurtosis() ~= -1.0
  doAssert statistics.kurtosisS() ~= -0.7000000000000008

from std/math import FloatClass, sqrt, pow, round

when defined(nimPreviewSlimSystem):
  import std/[assertions, formatfloat]

{.push debugger: off.} # the user does not want to trace a part
                       # of the standard library!
{.push checks: off, line_dir: off, stack_trace: off.}

type
  RunningStat* = object           ## An accumulator for statistical data.
    n*: int                       ## amount of pushed data
    min*, max*, sum*: float       ## self-explaining
    mom1, mom2, mom3, mom4: float ## statistical moments, mom1 is mean

  RunningRegress* = object ## An accumulator for regression calculations.
    n*: int                ## amount of pushed data
    x_stats*: RunningStat  ## stats for the first set of data
    y_stats*: RunningStat  ## stats for the second set of data
    s_xy: float            ## accumulated data for combined xy

# ----------- RunningStat --------------------------

proc clear*(s: var RunningStat) =
  ## Resets `s`.
  s.n = 0
  s.min = 0.0
  s.max = 0.0
  s.sum = 0.0
  s.mom1 = 0.0
  s.mom2 = 0.0
  s.mom3 = 0.0
  s.mom4 = 0.0

proc push*(s: var RunningStat, x: float) =
  ## Pushes a value `x` for processing.
  if s.n == 0:
    s.min = x
    s.max = x
  else:
    if s.min > x: s.min = x
    if s.max < x: s.max = x
  inc(s.n)
  # See Knuth TAOCP vol 2, 3rd edition, page 232
  s.sum += x
  let n = toFloat(s.n)
  let delta = x - s.mom1
  let delta_n = delta / toFloat(s.n)
  let delta_n2 = delta_n * delta_n
  let term1 = delta * delta_n * toFloat(s.n - 1)
  s.mom4 += term1 * delta_n2 * (n*n - 3*n + 3) +
              6*delta_n2*s.mom2 - 4*delta_n*s.mom3
  s.mom3 += term1 * delta_n * (n - 2) - 3*delta_n*s.mom2
  s.mom2 += term1
  s.mom1 += delta_n

proc push*(s: var RunningStat, x: int) =
  ## Pushes a value `x` for processing.
  ##
  ## `x` is simply converted to `float`
  ## and the other push operation is called.
  s.push(toFloat(x))

proc push*(s: var RunningStat, x: openArray[float|int]) =
  ## Pushes all values of `x` for processing.
  ##
  ## Int values of `x` are simply converted to `float` and
  ## the other push operation is called.
  for val in x:
    s.push(val)

proc mean*(s: RunningStat): float =
  ## Computes the current mean of `s`.
  result = s.mom1

proc variance*(s: RunningStat): float =
  ## Computes the current population variance of `s`.
  result = s.mom2 / toFloat(s.n)

proc varianceS*(s: RunningStat): float =
  ## Computes the current sample variance of `s`.
  if s.n > 1: result = s.mom2 / toFloat(s.n - 1)
  else: result = 0.0

proc standardDeviation*(s: RunningStat): float =
  ## Computes the current population standard deviation of `s`.
  result = sqrt(variance(s))

proc standardDeviationS*(s: RunningStat): float =
  ## Computes the current sample standard deviation of `s`.
  result = sqrt(varianceS(s))

proc skewness*(s: RunningStat): float =
  ## Computes the current population skewness of `s`.
  result = sqrt(toFloat(s.n)) * s.mom3 / pow(s.mom2, 1.5)

proc skewnessS*(s: RunningStat): float =
  ## Computes the current sample skewness of `s`.
  let s2 = skewness(s)
  result = sqrt(toFloat(s.n*(s.n-1)))*s2 / toFloat(s.n-2)

proc kurtosis*(s: RunningStat): float =
  ## Computes the current population kurtosis of `s`.
  result = toFloat(s.n) * s.mom4 / (s.mom2 * s.mom2) - 3.0

proc kurtosisS*(s: RunningStat): float =
  ## Computes the current sample kurtosis of `s`.
  result = toFloat(s.n-1) / toFloat((s.n-2)*(s.n-3)) *
              (toFloat(s.n+1)*kurtosis(s) + 6)

proc `+`*(a, b: RunningStat): RunningStat =
  ## Combines two `RunningStat`s.
  ##
  ## Useful when performing parallel analysis of data series
  ## and needing to re-combine parallel result sets.
  result = default(RunningStat)
  result.clear()
  result.n = a.n + b.n

  let delta = b.mom1 - a.mom1
  let delta2 = delta*delta
  let delta3 = delta*delta2
  let delta4 = delta2*delta2
  let n = toFloat(result.n)

  result.mom1 = (a.n.float*a.mom1 + b.n.float*b.mom1) / n
  result.mom2 = a.mom2 + b.mom2 + delta2 * a.n.float * b.n.float / n
  result.mom3 = a.mom3 + b.mom3 +
                delta3 * a.n.float * b.n.float * (a.n.float - b.n.float)/(n*n);
  result.mom3 += 3.0*delta * (a.n.float*b.mom2 - b.n.float*a.mom2) / n
  result.mom4 = a.mom4 + b.mom4 +
            delta4*a.n.float*b.n.float * toFloat(a.n*a.n - a.n*b.n + b.n*b.n) /
                (n*n*n)
  result.mom4 += 6.0*delta2 * (a.n.float*a.n.float*b.mom2 + b.n.float*b.n.float*a.mom2) /
                (n*n) +
                4.0*delta*(a.n.float*b.mom3 - b.n.float*a.mom3) / n
  result.max = max(a.max, b.max)
  result.min = min(a.min, b.min)

proc `+=`*(a: var RunningStat, b: RunningStat) {.inline.} =
  ## Adds the `RunningStat` `b` to `a`.
  a = a + b

proc `$`*(a: RunningStat): string =
  ## Produces a string representation of the `RunningStat`. The exact
  ## format is currently unspecified and subject to change. Currently
  ## it contains:
  ##
  ## - the number of probes
  ## - min, max values
  ## - sum, mean and standard deviation.
  result = "RunningStat(\n"
  result.add "  number of probes: " & $a.n & "\n"
  result.add "  max: " & $a.max & "\n"
  result.add "  min: " & $a.min & "\n"
  result.add "  sum: " & $a.sum & "\n"
  result.add "  mean: " & $a.mean & "\n"
  result.add "  std deviation: " & $a.standardDeviation & "\n"
  result.add ")"

# ---------------------- standalone array/seq stats ---------------------

proc mean*[T](x: openArray[T]): float =
  ## Computes the mean of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.mean()

proc variance*[T](x: openArray[T]): float =
  ## Computes the population variance of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.variance()

proc varianceS*[T](x: openArray[T]): float =
  ## Computes the sample variance of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.varianceS()

proc standardDeviation*[T](x: openArray[T]): float =
  ## Computes the population standard deviation of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.standardDeviation()

proc standardDeviationS*[T](x: openArray[T]): float =
  ## Computes the sample standard deviation of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.standardDeviationS()

proc skewness*[T](x: openArray[T]): float =
  ## Computes the population skewness of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.skewness()

proc skewnessS*[T](x: openArray[T]): float =
  ## Computes the sample skewness of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.skewnessS()

proc kurtosis*[T](x: openArray[T]): float =
  ## Computes the population kurtosis of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.kurtosis()

proc kurtosisS*[T](x: openArray[T]): float =
  ## Computes the sample kurtosis of `x`.
  var rs: RunningStat
  rs.push(x)
  result = rs.kurtosisS()

# ---------------------- Running Regression -----------------------------

proc clear*(r: var RunningRegress) =
  ## Resets `r`.
  r.x_stats.clear()
  r.y_stats.clear()
  r.s_xy = 0.0
  r.n = 0

proc push*(r: var RunningRegress, x, y: float) =
  ## Pushes two values `x` and `y` for processing.
  r.s_xy += (r.x_stats.mean() - x)*(r.y_stats.mean() - y) *
                toFloat(r.n) / toFloat(r.n + 1)
  r.x_stats.push(x)
  r.y_stats.push(y)
  inc(r.n)

proc push*(r: var RunningRegress, x, y: int) {.inline.} =
  ## Pushes two values `x` and `y` for processing.
  ##
  ## `x` and `y` are converted to `float`
  ## and the other push operation is called.
  r.push(toFloat(x), toFloat(y))

proc push*(r: var RunningRegress, x, y: openArray[float|int]) =
  ## Pushes two sets of values `x` and `y` for processing.
  assert(x.len == y.len)
  for i in 0..<x.len:
    r.push(x[i], y[i])

proc slope*(r: RunningRegress): float =
  ## Computes the current slope of `r`.
  let s_xx = r.x_stats.varianceS()*toFloat(r.n - 1)
  result = r.s_xy / s_xx

proc intercept*(r: RunningRegress): float =
  ## Computes the current intercept of `r`.
  result = r.y_stats.mean() - r.slope()*r.x_stats.mean()

proc correlation*(r: RunningRegress): float =
  ## Computes the current correlation of the two data
  ## sets pushed into `r`.
  let t = r.x_stats.standardDeviation() * r.y_stats.standardDeviation()
  result = r.s_xy / (toFloat(r.n) * t)

proc `+`*(a, b: RunningRegress): RunningRegress =
  ## Combines two `RunningRegress` objects.
  ##
  ## Useful when performing parallel analysis of data series
  ## and needing to re-combine parallel result sets
  result = default(RunningRegress)
  result.clear()
  result.x_stats = a.x_stats + b.x_stats
  result.y_stats = a.y_stats + b.y_stats
  result.n = a.n + b.n

  let delta_x = b.x_stats.mean() - a.x_stats.mean()
  let delta_y = b.y_stats.mean() - a.y_stats.mean()
  result.s_xy = a.s_xy + b.s_xy +
      toFloat(a.n*b.n)*delta_x*delta_y/toFloat(result.n)

proc `+=`*(a: var RunningRegress, b: RunningRegress) =
  ## Adds the `RunningRegress` `b` to `a`.
  a = a + b

{.pop.}
{.pop.}
