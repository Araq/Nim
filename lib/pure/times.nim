#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

##[
  The `times` module contains routines and types for dealing with time using
  the `proleptic Gregorian calendar<https://en.wikipedia.org/wiki/Proleptic_Gregorian_calendar>`_.
  It's also available for the
  `JavaScript target <backends.html#backends-the-javascript-target>`_.

  Although the `times` module supports nanosecond time resolution, the
  resolution used by `getTime()` depends on the platform and backend
  (JS is limited to millisecond precision).

  Examples
  ========

    ```nim
    import std/[times, os]
    # Simple benchmarking
    let time = cpuTime()
    sleep(100) # Replace this with something to be timed
    echo "Time taken: ", cpuTime() - time

    # Current date & time
    let now1 = now()     # Current timestamp as a DateTime in local time
    let now2 = now().utc # Current timestamp as a DateTime in UTC
    let now3 = getTime() # Current timestamp as a Time

    # Arithmetic using Duration
    echo "One hour from now      : ", now() + initDuration(hours = 1)
    # Arithmetic using TimeInterval
    echo "One year from now      : ", now() + 1.years
    echo "One month from now     : ", now() + 1.months
    ```

  Parsing and Formatting Dates
  ============================

  The `DateTime` type can be parsed and formatted using the different
  `parse` and `format` procedures.

    ```nim
    let dt = parse("2000-01-01", "yyyy-MM-dd")
    echo dt.format("yyyy-MM-dd")
    ```

  The different format patterns that are supported are documented below.

  ===========  =================================================================================  ==============================================
  Pattern      Description                                                                        Example
  ===========  =================================================================================  ==============================================
  `d`          Numeric value representing the day of the month,                                   | `1/04/2012 -> 1`
               it will be either one or two digits long.                                          | `21/04/2012 -> 21`
  `dd`         Same as above, but is always two digits.                                           | `1/04/2012 -> 01`
                                                                                                  | `21/04/2012 -> 21`
  `ddd`        Three letter string which indicates the day of the week.                           | `Saturday -> Sat`
                                                                                                  | `Monday -> Mon`
  `dddd`       Full string for the day of the week.                                               | `Saturday -> Saturday`
                                                                                                  | `Monday -> Monday`
  `GG`         The last two digits of the Iso Week-Year                                           | `30/12/2012 -> 13`
  `GGGG`       The Iso week-calendar year padded to four digits                                   | `30/12/2012 -> 2013`
  `h`          The hours in one digit if possible. Ranging from 1-12.                             | `5pm -> 5`
                                                                                                  | `2am -> 2`
  `hh`         The hours in two digits always. If the hour is one digit, 0 is prepended.          | `5pm -> 05`
                                                                                                  | `11am -> 11`
  `H`          The hours in one digit if possible, ranging from 0-23.                             | `5pm -> 17`
                                                                                                  | `2am -> 2`
  `HH`         The hours in two digits always. 0 is prepended if the hour is one digit.           | `5pm -> 17`
                                                                                                  | `2am -> 02`
  `m`          The minutes in one digit if possible.                                              | `5:30 -> 30`
                                                                                                  | `2:01 -> 1`
  `mm`         Same as above but always two digits, 0 is prepended if the minute is one digit.    | `5:30 -> 30`
                                                                                                  | `2:01 -> 01`
  `M`          The month in one digit if possible.                                                | `September -> 9`
                                                                                                  | `December -> 12`
  `MM`         The month in two digits always. 0 is prepended if the month value is one digit.    | `September -> 09`
                                                                                                  | `December -> 12`
  `MMM`        Abbreviated three-letter form of the month.                                        | `September -> Sep`
                                                                                                  | `December -> Dec`
  `MMMM`       Full month string, properly capitalized.                                           | `September -> September`
  `s`          Seconds as one digit if possible.                                                  | `00:00:06 -> 6`
  `ss`         Same as above but always two digits. 0 is prepended if the second is one digit.    | `00:00:06 -> 06`
  `t`          `A` when time is in the AM. `P` when time is in the PM.                            | `5pm -> P`
                                                                                                  | `2am -> A`
  `tt`         Same as above, but `AM` and `PM` instead of `A` and `P` respectively.              | `5pm -> PM`
                                                                                                  | `2am -> AM`
  `yy`         The last two digits of the year. When parsing, the current century is assumed.     | `2012 AD -> 12`
  `yyyy`       The year, padded to at least four digits.                                          | `2012 AD -> 2012`
               Is always positive, even when the year is BC.                                      | `24 AD -> 0024`
               When the year is more than four digits, '+' is prepended.                          | `24 BC -> 00024`
                                                                                                  | `12345 AD -> +12345`
  `YYYY`       The year without any padding.                                                      | `2012 AD -> 2012`
               Is always positive, even when the year is BC.                                      | `24 AD -> 24`
                                                                                                  | `24 BC -> 24`
                                                                                                  | `12345 AD -> 12345`
  `uuuu`       The year, padded to at least four digits. Will be negative when the year is BC.    | `2012 AD -> 2012`
               When the year is more than four digits, '+' is prepended unless the year is BC.    | `24 AD -> 0024`
                                                                                                  | `24 BC -> -0023`
                                                                                                  | `12345 AD -> +12345`
  `UUUU`       The year without any padding. Will be negative when the year is BC.                | `2012 AD -> 2012`
                                                                                                  | `24 AD -> 24`
                                                                                                  | `24 BC -> -23`
                                                                                                  | `12345 AD -> 12345`
  `V`          The Iso Week-Number as one or two digits                                           | `3/2/2012 -> 5`
                                                                                                  | `1/4/2012 -> 13`
  `VV`         The Iso Week-Number as two digits always. 0 is prepended if one digit.             | `3/2/2012 -> 05`
                                                                                                  | `1/4/2012 -> 13`
  `z`          Displays the timezone offset from UTC.                                             | `UTC+7 -> +7`
                                                                                                  | `UTC-5 -> -5`
  `zz`         Same as above but with leading 0.                                                  | `UTC+7 -> +07`
                                                                                                  | `UTC-5 -> -05`
  `zzz`        Same as above but with `:mm` where *mm* represents minutes.                        | `UTC+7 -> +07:00`
                                                                                                  | `UTC-5 -> -05:00`
  `ZZZ`        Same as above but with `mm` where *mm* represents minutes.                         | `UTC+7 -> +0700`
                                                                                                  | `UTC-5 -> -0500`
  `zzzz`       Same as above but with `:ss` where *ss* represents seconds.                        | `UTC+7 -> +07:00:00`
                                                                                                  | `UTC-5 -> -05:00:00`
  `ZZZZ`       Same as above but with `ss` where *ss* represents seconds.                         | `UTC+7 -> +070000`
                                                                                                  | `UTC-5 -> -050000`
  `g`          Era: AD or BC                                                                      | `300 AD -> AD`
                                                                                                  | `300 BC -> BC`
  `fff`        Milliseconds display                                                               | `1000000 nanoseconds -> 1`
  `ffffff`     Microseconds display                                                               | `1000000 nanoseconds -> 1000`
  `fffffffff`  Nanoseconds display                                                                | `1000000 nanoseconds -> 1000000`
  ===========  =================================================================================  ==============================================

  Other strings can be inserted by putting them in `''`. For example
  `hh'->'mm` will give `01->56`.  In addition to spaces,
  the following characters can be inserted without quoting them:
  `:` `-` `,` `.` `(` `)` `/` `[` `]`.
  A literal `'` can be specified with `''`.

  However you don't need to necessarily separate format patterns, as an
  unambiguous format string like `yyyyMMddhhmmss` is also valid (although
  only for years in the range 1..9999).

  Duration vs TimeInterval
  ============================
  The `times` module exports two similar types that are both used to
  represent some amount of time: `Duration <#Duration>`_ and
  `TimeInterval <#TimeInterval>`_.
  This section explains how they differ and when one should be preferred over the
  other (short answer: use `Duration` unless support for months and years is
  needed).

  Duration
  ----------------------------
  A `Duration` represents a duration of time stored as seconds and
  nanoseconds. A `Duration` is always fully normalized, so
  `initDuration(hours = 1)` and `initDuration(minutes = 60)` are equivalent.

  Arithmetic with a `Duration` is very fast, especially when used with the
  `Time` type, since it only involves basic arithmetic. Because `Duration`
  is more performant and easier to understand it should generally preferred.

  TimeInterval
  ----------------------------
  A `TimeInterval` represents an amount of time expressed in calendar
  units, for example "1 year and 2 days". Since some units cannot be
  normalized (the length of a year is different for leap years for example),
  the `TimeInterval` type uses separate fields for every unit. The
  `TimeInterval`'s returned from this module generally don't normalize
  **anything**, so even units that could be normalized (like seconds,
  milliseconds and so on) are left untouched.

  Arithmetic with a `TimeInterval` can be very slow, because it requires
  timezone information.

  Since it's slower and more complex, the `TimeInterval` type should be
  avoided unless the program explicitly needs the features it offers that
  `Duration` doesn't have.

  How long is a day?
  ----------------------------
  It should be especially noted that the handling of days differs between
  `TimeInterval` and `Duration`. The `Duration` type always treats a day
  as exactly 86400 seconds. For `TimeInterval`, it's more complex.

  As an example, consider the amount of time between these two timestamps, both
  in the same timezone:

    - 2018-03-25T12:00+02:00
    - 2018-03-26T12:00+01:00

  If only the date & time is considered, it appears that exactly one day has
  passed. However, the UTC offsets are different, which means that the
  UTC offset was changed somewhere in between. This happens twice each year for
  timezones that use daylight savings time. Because of this change, the amount
  of time that has passed is actually 25 hours.

  The `TimeInterval` type uses calendar units, and will say that exactly one
  day has passed. The `Duration` type on the other hand normalizes everything
  to seconds, and will therefore say that 90000 seconds has passed, which is
  the same as 25 hours.

  See also
  ========
  * `monotimes module <monotimes.html>`_
]##

import std/[strutils, math, options]

import std/private/since
include "system/inclrtl"

when defined(nimPreviewSlimSystem):
  import std/assertions


when defined(js):
  import std/jscore
  import std/private/jsutils

  when jsNoBigInt64:
    # This is really bad, but overflow checks are broken badly for
    # ints on the JS backend. See #6752.
    {.push overflowChecks: off.}
    proc `*`(a, b: int64): int64 =
      system.`*`(a, b)
    proc `*`(a, b: int): int =
      system.`*`(a, b)
    proc `+`(a, b: int64): int64 =
      system.`+`(a, b)
    proc `+`(a, b: int): int =
      system.`+`(a, b)
    proc `-`(a, b: int64): int64 =
      system.`-`(a, b)
    proc `-`(a, b: int): int =
      system.`-`(a, b)
    proc inc(a: var int, b: int) =
      system.inc(a, b)
    proc inc(a: var int64, b: int) =
      system.inc(a, b)
    {.pop.}

elif defined(posix):
  import std/posix

  type CTime = posix.Time

  when defined(macosx):
    proc gettimeofday(tp: var Timeval, unused: pointer = nil)
      {.importc: "gettimeofday", header: "<sys/time.h>", sideEffect.}

elif defined(windows):
  import std/winlean, std/time_t

  type
    CTime = time_t.Time
    Tm {.importc: "struct tm", header: "<time.h>", final, pure.} = object
      tm_sec*: cint   ## Seconds [0,60].
      tm_min*: cint   ## Minutes [0,59].
      tm_hour*: cint  ## Hour [0,23].
      tm_mday*: cint  ## Day of month [1,31].
      tm_mon*: cint   ## Month of year [0,11].
      tm_year*: cint  ## Years since 1900.
      tm_wday*: cint  ## Day of week [0,6] (Sunday =0).
      tm_yday*: cint  ## Day of year [0,365].
      tm_isdst*: cint ## Daylight Savings flag.

  proc localtime(a1: var CTime): ptr Tm {.importc, header: "<time.h>", sideEffect.}

type
  Month* = enum ## Represents a month. Note that the enum starts at `1`,
                ## so `ord(month)` will give the month number in the
                ## range `1..12`.
    mJan = (1, "January")
    mFeb = "February"
    mMar = "March"
    mApr = "April"
    mMay = "May"
    mJun = "June"
    mJul = "July"
    mAug = "August"
    mSep = "September"
    mOct = "October"
    mNov = "November"
    mDec = "December"

  WeekDay* = enum ## Represents a weekday.
    dMon = "Monday"
    dTue = "Tuesday"
    dWed = "Wednesday"
    dThu = "Thursday"
    dFri = "Friday"
    dSat = "Saturday"
    dSun = "Sunday"

type
  MonthdayRange* = range[1..31]
  HourRange* = range[0..23]
  MinuteRange* = range[0..59]
  SecondRange* = range[0..60] ## \
    ## Includes the value 60 to allow for a leap second. Note however
    ## that the `second` of a `DateTime` will never be a leap second.
  YeardayRange* = range[0..365]
  NanosecondRange* = range[0..999_999_999]

  IsoWeekRange* = range[1 .. 53]
    ## An ISO 8601 calendar week number.
  IsoYear* = distinct int
    ## An ISO 8601 calendar year number.
    ##
    ## .. warning:: The ISO week-based year can correspond to the following or previous year from 29 December to January 3.

  Time* = object ## Represents a point in time.
    seconds: int64
    nanosecond: NanosecondRange

  DateTime* = object of RootObj  ## \
    ## Represents a time in different parts. Although this type can represent
    ## leap seconds, they are generally not supported in this module. They are
    ## not ignored, but the `DateTime`'s returned by procedures in this
    ## module will never have a leap second.
    nanosecond: NanosecondRange
    second: SecondRange
    minute: MinuteRange
    hour: HourRange
    monthdayZero: int
    monthZero: int
    year: int
    weekday: WeekDay
    yearday: YeardayRange
    isDst: bool
    timezone: Timezone
    utcOffset: int

  Duration* = object ## Represents a fixed duration of time, meaning a duration
                     ## that has constant length independent of the context.
                     ##
                     ## To create a new `Duration`, use `initDuration
                     ## <#initDuration,int64,int64,int64,int64,int64,int64,int64,int64>`_.
                     ## Instead of trying to access the private attributes, use
                     ## `inSeconds <#inSeconds,Duration>`_ for converting to seconds and
                     ## `inNanoseconds <#inNanoseconds,Duration>`_ for converting to nanoseconds.
    seconds: int64
    nanosecond: NanosecondRange

  TimeUnit* = enum ## Different units of time.
    Nanoseconds, Microseconds, Milliseconds, Seconds, Minutes, Hours, Days,
    Weeks, Months, Years

  FixedTimeUnit* = range[Nanoseconds..Weeks] ## \
      ## Subrange of `TimeUnit` that only includes units of fixed duration.
      ## These are the units that can be represented by a `Duration`.

  TimeInterval* = object ## \
      ## Represents a non-fixed duration of time. Can be used to add and
      ## subtract non-fixed time units from a `DateTime <#DateTime>`_ or
      ## `Time <#Time>`_.
      ##
      ## Create a new `TimeInterval` with `initTimeInterval proc
      ## <#initTimeInterval,int,int,int,int,int,int,int,int,int,int>`_.
      ##
      ## Note that `TimeInterval` doesn't represent a fixed duration of time,
      ## since the duration of some units depend on the context (e.g a year
      ## can be either 365 or 366 days long). The non-fixed time units are
      ## years, months, days and week.
      ##
      ## Note that `TimeInterval`'s returned from the `times` module are
      ## never normalized. If you want to normalize a time unit,
      ## `Duration <#Duration>`_ should be used instead.
    nanoseconds*: int    ## The number of nanoseconds
    microseconds*: int   ## The number of microseconds
    milliseconds*: int   ## The number of milliseconds
    seconds*: int        ## The number of seconds
    minutes*: int        ## The number of minutes
    hours*: int          ## The number of hours
    days*: int           ## The number of days
    weeks*: int          ## The number of weeks
    months*: int         ## The number of months
    years*: int          ## The number of years

  Timezone* = ref object ## \
      ## Timezone interface for supporting `DateTime <#DateTime>`_\s of arbitrary
      ## timezones. The `times` module only supplies implementations for the
      ## system's local time and UTC.
    zonedTimeFromTimeImpl: proc (x: Time): ZonedTime
        {.tags: [], raises: [], benign.}
    zonedTimeFromAdjTimeImpl: proc (x: Time): ZonedTime
        {.tags: [], raises: [], benign.}
    name: string

  ZonedTime* = object ## Represents a point in time with an associated
                      ## UTC offset and DST flag. This type is only used for
                      ## implementing timezones.
    time*: Time       ## The point in time being represented.
    utcOffset*: int   ## The offset in seconds west of UTC,
                      ## including any offset due to DST.
    isDst*: bool      ## Determines whether DST is in effect.

  DurationParts* = array[FixedTimeUnit, int64] # Array of Duration parts starts
  TimeIntervalParts* = array[TimeUnit, int] # Array of Duration parts starts

const
  secondsInMin = 60
  secondsInHour = 60*60
  secondsInDay = 60*60*24
  rateDiff = 10000000'i64 # 100 nsecs
                          # The number of hectonanoseconds between 1601/01/01 (windows epoch)
                          # and 1970/01/01 (unix epoch).
  epochDiff = 116444736000000000'i64

const unitWeights: array[FixedTimeUnit, int64] = [
  1'i64,
  1000,
  1_000_000,
  1e9.int64,
  secondsInMin * 1e9.int64,
  secondsInHour * 1e9.int64,
  secondsInDay * 1e9.int64,
  7 * secondsInDay * 1e9.int64,
]

when (NimMajor, NimMinor) >= (1, 4):
  # Newer versions of Nim don't track defects
  {.pragma: parseFormatRaises, raises: [TimeParseError, TimeFormatParseError].}
  {.pragma: parseRaises, raises: [TimeParseError].}
else:
  # Still track when using older versions
  {.pragma: parseFormatRaises, raises: [TimeParseError, TimeFormatParseError, Defect].}
  {.pragma: parseRaises, raises: [TimeParseError, Defect].}


#
# Helper procs
#

{.pragma: operator, rtl, noSideEffect, benign.}

proc convert*[T: SomeInteger](unitFrom, unitTo: FixedTimeUnit, quantity: T): T
    {.inline.} =
  ## Convert a quantity of some duration unit to another duration unit.
  ## This proc only deals with integers, so the result might be truncated.
  runnableExamples:
    doAssert convert(Days, Hours, 2) == 48
    doAssert convert(Days, Weeks, 13) == 1 # Truncated
    doAssert convert(Seconds, Milliseconds, -1) == -1000
  if unitFrom < unitTo:
    (quantity div (unitWeights[unitTo] div unitWeights[unitFrom])).T
  else:
    ((unitWeights[unitFrom] div unitWeights[unitTo]) * quantity).T

proc normalize[T: Duration|Time](seconds, nanoseconds: int64): T =
  ## Normalize a (seconds, nanoseconds) pair and return it as either
  ## a `Duration` or `Time`. A normalized `Duration|Time` has a
  ## positive nanosecond part in the range `NanosecondRange`.
  result = default(T)
  result.seconds = seconds + convert(Nanoseconds, Seconds, nanoseconds)
  var nanosecond = nanoseconds mod convert(Seconds, Nanoseconds, 1)
  if nanosecond < 0:
    nanosecond += convert(Seconds, Nanoseconds, 1)
    result.seconds -= 1
  result.nanosecond = nanosecond.int

proc isLeapYear*(year: int): bool =
  ## Returns true if `year` is a leap year.
  runnableExamples:
    doAssert isLeapYear(2000)
    doAssert not isLeapYear(1900)
  year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0)

proc getDaysInMonth*(month: Month, year: int): int =
  ## Get the number of days in `month` of `year`.
  # http://www.dispersiondesign.com/articles/time/number_of_days_in_a_month
  runnableExamples:
    doAssert getDaysInMonth(mFeb, 2000) == 29
    doAssert getDaysInMonth(mFeb, 2001) == 28
  case month
  of mFeb: result = if isLeapYear(year): 29 else: 28
  of mApr, mJun, mSep, mNov: result = 30
  else: result = 31

proc assertValidDate(monthday: MonthdayRange, month: Month, year: int)
    {.inline.} =
  assert monthday <= getDaysInMonth(month, year),
    $year & "-" & intToStr(ord(month), 2) & "-" & $monthday &
      " is not a valid date"

proc toEpochDay(monthday: MonthdayRange, month: Month, year: int): int64 =
  ## Get the epoch day from a year/month/day date.
  ## The epoch day is the number of days since 1970/01/01
  ## (it might be negative).
  # Based on https://howardhinnant.github.io/date_algorithms.html
  assertValidDate monthday, month, year
  var (y, m, d) = (year, ord(month), monthday.int)
  if m <= 2:
    y.dec

  let era = (if y >= 0: y else: y-399) div 400
  let yoe = y - era * 400
  let doy = (153 * (m + (if m > 2: -3 else: 9)) + 2) div 5 + d-1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  return era * 146097 + doe - 719468

proc fromEpochDay(epochday: int64):
    tuple[monthday: MonthdayRange, month: Month, year: int] =
  ## Get the year/month/day date from a epoch day.
  ## The epoch day is the number of days since 1970/01/01
  ## (it might be negative).
  # Based on https://howardhinnant.github.io/date_algorithms.html
  var z = epochday
  z.inc 719468
  let era = (if z >= 0: z else: z - 146096) div 146097
  let doe = z - era * 146097
  let yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365
  let y = yoe + era * 400;
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let d = doy - (153 * mp + 2) div 5 + 1
  let m = mp + (if mp < 10: 3 else: -9)
  return (d.MonthdayRange, m.Month, (y + ord(m <= 2)).int)

proc getDayOfYear*(monthday: MonthdayRange, month: Month, year: int):
    YeardayRange {.tags: [], raises: [], benign.} =
  ## Returns the day of the year.
  ## Equivalent with `dateTime(year, month, monthday, 0, 0, 0, 0).yearday`.
  runnableExamples:
    doAssert getDayOfYear(1, mJan, 2000) == 0
    doAssert getDayOfYear(10, mJan, 2000) == 9
    doAssert getDayOfYear(10, mFeb, 2000) == 40

  assertValidDate monthday, month, year
  const daysUntilMonth: array[Month, int] =
    [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
  const daysUntilMonthLeap: array[Month, int] =
    [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]

  if isLeapYear(year):
    result = daysUntilMonthLeap[month] + monthday - 1
  else:
    result = daysUntilMonth[month] + monthday - 1

proc getDayOfWeek*(monthday: MonthdayRange, month: Month, year: int): WeekDay
    {.tags: [], raises: [], benign.} =
  ## Returns the day of the week enum from day, month and year.
  ## Equivalent with `dateTime(year, month, monthday, 0, 0, 0, 0).weekday`.
  runnableExamples:
    doAssert getDayOfWeek(13, mJun, 1990) == dWed
    doAssert $getDayOfWeek(13, mJun, 1990) == "Wednesday"

  assertValidDate monthday, month, year
  # 1970-01-01 is a Thursday, we adjust to the previous Monday
  let days = toEpochDay(monthday, month, year) - 3
  let weeks = floorDiv(days, 7'i64)
  let wd = days - weeks * 7
  # The value of d is 0 for a Sunday, 1 for a Monday, 2 for a Tuesday, etc.
  # so we must correct for the WeekDay type.
  result = if wd == 0: dSun else: WeekDay(wd - 1)

proc getDaysInYear*(year: int): int =
  ## Get the number of days in a `year`
  runnableExamples:
    doAssert getDaysInYear(2000) == 366
    doAssert getDaysInYear(2001) == 365
  result = 365 + (if isLeapYear(year): 1 else: 0)

proc `==`*(a, b: IsoYear): bool {.borrow.}
proc `$`*(p: IsoYear): string {.borrow.}

proc getWeeksInIsoYear*(y: IsoYear): IsoWeekRange {.since: (1, 5).} =
  ## Returns the number of weeks in the specified ISO 8601 week-based year, which can be
  ## either 53 or 52.
  runnableExamples:
    assert getWeeksInIsoYear(IsoYear(2019)) == 52
    assert getWeeksInIsoYear(IsoYear(2020)) == 53

  var y = int(y)

  # support negative years
  y = if y < 0: 400 + y mod 400 else: y

  # source: https://webspace.science.uu.nl/~gent0113/calendar/isocalendar.htm
  let p = (y + (y div 4) - (y div 100) + (y div 400)) mod 7
  let y1 = y - 1
  let p1 = (y1 + (y1 div 4) - (y1 div 100) + (y1 div 400)) mod 7
  if p == 4 or p1 == 3: 53 else: 52

proc getIsoWeekAndYear*(dt: DateTime):
  tuple[isoweek: IsoWeekRange, isoyear: IsoYear] {.since: (1, 5).} =
  ## Returns the ISO 8601 week and year.
  ##
  ## .. warning:: The ISO week-based year can correspond to the following or previous year from 29 December to January 3.
  runnableExamples:
    assert getIsoWeekAndYear(initDateTime(21, mApr, 2018, 00, 00, 00)) == (isoweek: 16.IsoWeekRange, isoyear: 2018.IsoYear)
    block:
      let (w, y) = getIsoWeekAndYear(initDateTime(30, mDec, 2019, 00, 00, 00))
      assert w == 01.IsoWeekRange
      assert y == 2020.IsoYear
    assert getIsoWeekAndYear(initDateTime(13, mSep, 2020, 00, 00, 00)) == (isoweek: 37.IsoWeekRange, isoyear: 2020.IsoYear)
    block:
      let (w, y) = getIsoWeekAndYear(initDateTime(2, mJan, 2021, 00, 00, 00))
      assert w.int > 52
      assert w.int < 54
      assert y.int mod 100 == 20

  # source: https://webspace.science.uu.nl/~gent0113/calendar/isocalendar.htm
  var w = (dt.yearday.int - dt.weekday.int + 10) div 7
  if w < 1:
    (isoweek: getWeeksInIsoYear(IsoYear(dt.year - 1)), isoyear: IsoYear(dt.year - 1))
  elif (w > getWeeksInIsoYear(IsoYear(dt.year))):
    (isoweek: IsoWeekRange(1), isoyear: IsoYear(dt.year + 1))
  else:
    (isoweek: IsoWeekRange(w), isoyear: IsoYear(dt.year))

proc stringifyUnit(value: int | int64, unit: TimeUnit): string =
  ## Stringify time unit with it's name, lowercased
  let strUnit = $unit
  result = ""
  result.addInt value
  result.add ' '
  if abs(value) != 1:
    result.add(strUnit.toLowerAscii())
  else:
    result.add(strUnit[0..^2].toLowerAscii())

proc humanizeParts(parts: seq[string]): string =
  ## Make date string parts human-readable
  result = ""
  if parts.len == 0:
    result.add "0 nanoseconds"
  elif parts.len == 1:
    result = parts[0]
  elif parts.len == 2:
    result = parts[0] & " and " & parts[1]
  else:
    for i in 0..high(parts)-1:
      result.add parts[i] & ", "
    result.add "and " & parts[high(parts)]

template subImpl[T: Duration|Time](a: Duration|Time, b: Duration|Time): T =
  normalize[T](a.seconds - b.seconds, a.nanosecond - b.nanosecond)

template addImpl[T: Duration|Time](a: Duration|Time, b: Duration|Time): T =
  normalize[T](a.seconds + b.seconds, a.nanosecond + b.nanosecond)

template ltImpl(a: Duration|Time, b: Duration|Time): bool =
  a.seconds < b.seconds or (
    a.seconds == b.seconds and a.nanosecond < b.nanosecond)

template lqImpl(a: Duration|Time, b: Duration|Time): bool =
  a.seconds < b.seconds or (
    a.seconds == b.seconds and a.nanosecond <= b.nanosecond)

template eqImpl(a: Duration|Time, b: Duration|Time): bool =
  a.seconds == b.seconds and a.nanosecond == b.nanosecond

#
# Duration
#

const DurationZero* = Duration() ## \
  ## Zero value for durations. Useful for comparisons.
  ##   ```nim
  ##   doAssert initDuration(seconds = 1) > DurationZero
  ##   doAssert initDuration(seconds = 0) == DurationZero
  ##   ```

proc initDuration*(nanoseconds, microseconds, milliseconds,
                   seconds, minutes, hours, days, weeks: int64 = 0): Duration =
  ## Create a new `Duration <#Duration>`_.
  runnableExamples:
    let dur = initDuration(seconds = 1, milliseconds = 1)
    doAssert dur.inMilliseconds == 1001
    doAssert dur.inSeconds == 1

  let seconds = convert(Weeks, Seconds, weeks) +
    convert(Days, Seconds, days) +
    convert(Minutes, Seconds, minutes) +
    convert(Hours, Seconds, hours) +
    convert(Seconds, Seconds, seconds) +
    convert(Milliseconds, Seconds, milliseconds) +
    convert(Microseconds, Seconds, microseconds) +
    convert(Nanoseconds, Seconds, nanoseconds)
  let nanoseconds = (convert(Milliseconds, Nanoseconds, milliseconds mod 1000) +
    convert(Microseconds, Nanoseconds, microseconds mod 1_000_000) +
    nanoseconds mod 1_000_000_000).int
  # Nanoseconds might be negative so we must normalize.
  result = normalize[Duration](seconds, nanoseconds)

template convert(dur: Duration, unit: static[FixedTimeUnit]): int64 =
  # The correction is required due to how durations are normalized.
  # For example,` initDuration(nanoseconds = -1)` is stored as
  # { seconds = -1, nanoseconds = 999999999 }.
  when unit == Nanoseconds:
    dur.seconds * 1_000_000_000 + dur.nanosecond
  else:
    let correction = dur.seconds < 0 and dur.nanosecond > 0
    when unit >= Seconds:
      convert(Seconds, unit, dur.seconds + ord(correction))
    else:
      if correction:
        convert(Seconds, unit, dur.seconds + 1) -
          convert(Nanoseconds, unit,
            convert(Seconds, Nanoseconds, 1) - dur.nanosecond)
      else:
        convert(Seconds, unit, dur.seconds) +
          convert(Nanoseconds, unit, dur.nanosecond)

proc inWeeks*(dur: Duration): int64 =
  ## Converts the duration to the number of whole weeks.
  runnableExamples:
    let dur = initDuration(days = 8)
    doAssert dur.inWeeks == 1
  dur.convert(Weeks)

proc inDays*(dur: Duration): int64 =
  ## Converts the duration to the number of whole days.
  runnableExamples:
    let dur = initDuration(hours = -50)
    doAssert dur.inDays == -2
  dur.convert(Days)

proc inHours*(dur: Duration): int64 =
  ## Converts the duration to the number of whole hours.
  runnableExamples:
    let dur = initDuration(minutes = 60, days = 2)
    doAssert dur.inHours == 49
  dur.convert(Hours)

proc inMinutes*(dur: Duration): int64 =
  ## Converts the duration to the number of whole minutes.
  runnableExamples:
    let dur = initDuration(hours = 2, seconds = 10)
    doAssert dur.inMinutes == 120
  dur.convert(Minutes)

proc inSeconds*(dur: Duration): int64 =
  ## Converts the duration to the number of whole seconds.
  runnableExamples:
    let dur = initDuration(hours = 2, milliseconds = 10)
    doAssert dur.inSeconds == 2 * 60 * 60
  dur.convert(Seconds)

proc inMilliseconds*(dur: Duration): int64 =
  ## Converts the duration to the number of whole milliseconds.
  runnableExamples:
    let dur = initDuration(seconds = -2)
    doAssert dur.inMilliseconds == -2000
  dur.convert(Milliseconds)

proc inMicroseconds*(dur: Duration): int64 =
  ## Converts the duration to the number of whole microseconds.
  runnableExamples:
    let dur = initDuration(seconds = -2)
    doAssert dur.inMicroseconds == -2000000
  dur.convert(Microseconds)

proc inNanoseconds*(dur: Duration): int64 =
  ## Converts the duration to the number of whole nanoseconds.
  runnableExamples:
    let dur = initDuration(seconds = -2)
    doAssert dur.inNanoseconds == -2000000000
  dur.convert(Nanoseconds)

proc toParts*(dur: Duration): DurationParts =
  ## Converts a duration into an array consisting of fixed time units.
  ##
  ## Each value in the array gives information about a specific unit of
  ## time, for example `result[Days]` gives a count of days.
  ##
  ## This procedure is useful for converting `Duration` values to strings.
  runnableExamples:
    var dp = toParts(initDuration(weeks = 2, days = 1))
    doAssert dp[Days] == 1
    doAssert dp[Weeks] == 2
    doAssert dp[Minutes] == 0
    dp = toParts(initDuration(days = -1))
    doAssert dp[Days] == -1

  var remS = dur.seconds
  var remNs = dur.nanosecond.int

  # Ensure the same sign for seconds and nanoseconds
  if remS < 0 and remNs != 0:
    remNs -= convert(Seconds, Nanoseconds, 1)
    remS.inc 1

  for unit in countdown(Weeks, Seconds):
    let quantity = convert(Seconds, unit, remS)
    remS = remS mod convert(unit, Seconds, 1)

    result[unit] = quantity

  for unit in countdown(Milliseconds, Nanoseconds):
    let quantity = convert(Nanoseconds, unit, remNs)
    remNs = remNs mod convert(unit, Nanoseconds, 1)

    result[unit] = quantity

proc `$`*(dur: Duration): string =
  ## Human friendly string representation of a `Duration`.
  runnableExamples:
    doAssert $initDuration(seconds = 2) == "2 seconds"
    doAssert $initDuration(weeks = 1, days = 2) == "1 week and 2 days"
    doAssert $initDuration(hours = 1, minutes = 2, seconds = 3) ==
      "1 hour, 2 minutes, and 3 seconds"
    doAssert $initDuration(milliseconds = -1500) ==
      "-1 second and -500 milliseconds"
  var parts = newSeq[string]()
  var numParts = toParts(dur)

  for unit in countdown(Weeks, Nanoseconds):
    let quantity = numParts[unit]
    if quantity != 0.int64:
      parts.add(stringifyUnit(quantity, unit))

  result = humanizeParts(parts)

proc `+`*(a, b: Duration): Duration {.operator, extern: "ntAddDuration".} =
  ## Add two durations together.
  runnableExamples:
    doAssert initDuration(seconds = 1) + initDuration(days = 1) ==
      initDuration(seconds = 1, days = 1)
  addImpl[Duration](a, b)

proc `-`*(a, b: Duration): Duration {.operator, extern: "ntSubDuration".} =
  ## Subtract a duration from another.
  runnableExamples:
    doAssert initDuration(seconds = 1, days = 1) - initDuration(seconds = 1) ==
      initDuration(days = 1)
  subImpl[Duration](a, b)

proc `-`*(a: Duration): Duration {.operator, extern: "ntReverseDuration".} =
  ## Reverse a duration.
  runnableExamples:
    doAssert -initDuration(seconds = 1) == initDuration(seconds = -1)
  normalize[Duration](-a.seconds, -a.nanosecond)

proc `<`*(a, b: Duration): bool {.operator, extern: "ntLtDuration".} =
  ## Note that a duration can be negative,
  ## so even if `a < b` is true `a` might
  ## represent a larger absolute duration.
  ## Use `abs(a) < abs(b)` to compare the absolute
  ## duration.
  runnableExamples:
    doAssert initDuration(seconds = 1) < initDuration(seconds = 2)
    doAssert initDuration(seconds = -2) < initDuration(seconds = 1)
    doAssert initDuration(seconds = -2).abs < initDuration(seconds = 1).abs == false
  ltImpl(a, b)

proc `<=`*(a, b: Duration): bool {.operator, extern: "ntLeDuration".} =
  lqImpl(a, b)

proc `==`*(a, b: Duration): bool {.operator, extern: "ntEqDuration".} =
  runnableExamples:
    let
      d1 = initDuration(weeks = 1)
      d2 = initDuration(days = 7)
    doAssert d1 == d2
  eqImpl(a, b)

proc `*`*(a: int64, b: Duration): Duration {.operator,
    extern: "ntMulInt64Duration".} =
  ## Multiply a duration by some scalar.
  runnableExamples:
    doAssert 5 * initDuration(seconds = 1) == initDuration(seconds = 5)
    doAssert 3 * initDuration(minutes = 45) == initDuration(hours = 2, minutes = 15)
  normalize[Duration](a * b.seconds, a * b.nanosecond)

proc `*`*(a: Duration, b: int64): Duration {.operator,
    extern: "ntMulDuration".} =
  ## Multiply a duration by some scalar.
  runnableExamples:
    doAssert initDuration(seconds = 1) * 5 == initDuration(seconds = 5)
    doAssert initDuration(minutes = 45) * 3 == initDuration(hours = 2, minutes = 15)
  b * a

proc `+=`*(d1: var Duration, d2: Duration) =
  d1 = d1 + d2

proc `-=`*(dt: var Duration, ti: Duration) =
  dt = dt - ti

proc `*=`*(a: var Duration, b: int) =
  a = a * b

proc `div`*(a: Duration, b: int64): Duration {.operator,
    extern: "ntDivDuration".} =
  ## Integer division for durations.
  runnableExamples:
    doAssert initDuration(seconds = 3) div 2 ==
      initDuration(milliseconds = 1500)
    doAssert initDuration(minutes = 45) div 30 ==
      initDuration(minutes = 1, seconds = 30)
    doAssert initDuration(nanoseconds = 3) div 2 ==
      initDuration(nanoseconds = 1)
  let carryOver = convert(Seconds, Nanoseconds, a.seconds mod b)
  normalize[Duration](a.seconds div b, (a.nanosecond + carryOver) div b)

proc high*(typ: typedesc[Duration]): Duration =
  ## Get the longest representable duration.
  initDuration(seconds = high(int64), nanoseconds = high(NanosecondRange))

proc low*(typ: typedesc[Duration]): Duration =
  ## Get the longest representable duration of negative direction.
  initDuration(seconds = low(int64))

proc abs*(a: Duration): Duration =
  runnableExamples:
    doAssert initDuration(milliseconds = -1500).abs ==
      initDuration(milliseconds = 1500)
  initDuration(seconds = abs(a.seconds), nanoseconds = -a.nanosecond)

#
# Time
#

proc initTime*(unix: int64, nanosecond: NanosecondRange): Time =
  ## Create a `Time <#Time>`_ from a unix timestamp and a nanosecond part.
  result = Time(seconds: unix, nanosecond: nanosecond)

proc nanosecond*(time: Time): NanosecondRange =
  ## Get the fractional part of a `Time` as the number
  ## of nanoseconds of the second.
  time.nanosecond

proc fromUnix*(unix: int64): Time
    {.benign, tags: [], raises: [], noSideEffect.} =
  ## Convert a unix timestamp (seconds since `1970-01-01T00:00:00Z`)
  ## to a `Time`.
  runnableExamples:
    doAssert $fromUnix(0).utc == "1970-01-01T00:00:00Z"
  initTime(unix, 0)

proc toUnix*(t: Time): int64 {.benign, tags: [], raises: [], noSideEffect.} =
  ## Convert `t` to a unix timestamp (seconds since `1970-01-01T00:00:00Z`).
  ## See also `toUnixFloat` for subsecond resolution.
  runnableExamples:
    doAssert fromUnix(0).toUnix() == 0
  t.seconds

proc fromUnixFloat(seconds: float): Time {.benign, tags: [], raises: [], noSideEffect.} =
  ## Convert a unix timestamp in seconds to a `Time`; same as `fromUnix`
  ## but with subsecond resolution.
  runnableExamples:
    doAssert fromUnixFloat(123456.0) == fromUnixFloat(123456)
    doAssert fromUnixFloat(-123456.0) == fromUnixFloat(-123456)
  let secs = seconds.floor
  let nsecs = (seconds - secs) * 1e9
  initTime(secs.int64, nsecs.NanosecondRange)

proc toUnixFloat(t: Time): float {.benign, tags: [], raises: [].} =
  ## Same as `toUnix` but using subsecond resolution.
  runnableExamples:
    let t = getTime()
    # `<` because of rounding errors
    doAssert abs(t.toUnixFloat().fromUnixFloat - t) < initDuration(nanoseconds = 1000)
  t.seconds.float + t.nanosecond / convert(Seconds, Nanoseconds, 1)

since((1, 1)):
  export fromUnixFloat
  export toUnixFloat


proc fromWinTime*(win: int64): Time =
  ## Convert a Windows file time (100-nanosecond intervals since
  ## `1601-01-01T00:00:00Z`) to a `Time`.
  const hnsecsPerSec = convert(Seconds, Nanoseconds, 1) div 100
  let nanos = floorMod(win, hnsecsPerSec) * 100
  let seconds = floorDiv(win - epochDiff, hnsecsPerSec)
  result = initTime(seconds, nanos)

proc toWinTime*(t: Time): int64 =
  ## Convert `t` to a Windows file time (100-nanosecond intervals
  ## since `1601-01-01T00:00:00Z`).
  result = t.seconds * rateDiff + epochDiff + t.nanosecond div 100

proc getTimeImpl(typ: typedesc[Time]): Time =
  raiseAssert "implemented in the vm"

proc getTime*(): Time {.tags: [TimeEffect], benign.} =
  ## Gets the current time as a `Time` with up to nanosecond resolution.
  when nimvm:
    result = getTimeImpl(Time)
  else:
    when defined(js):
      let millis = newDate().getTime()
      let seconds = convert(Milliseconds, Seconds, millis)
      let nanos = convert(Milliseconds, Nanoseconds,
        millis mod convert(Seconds, Milliseconds, 1).int)
      result = initTime(seconds, nanos)
    elif defined(macosx):
      var a {.noinit.}: Timeval
      gettimeofday(a)
      result = initTime(a.tv_sec.int64,
                        convert(Microseconds, Nanoseconds, a.tv_usec.int))
    elif defined(posix):
      var ts {.noinit.}: Timespec
      discard clock_gettime(CLOCK_REALTIME, ts)
      result = initTime(ts.tv_sec.int64, ts.tv_nsec.int)
    elif defined(windows):
      var f {.noinit.}: FILETIME
      getSystemTimeAsFileTime(f)
      result = fromWinTime(rdFileTime(f))

proc `-`*(a, b: Time): Duration {.operator, extern: "ntDiffTime".} =
  ## Computes the duration between two points in time.
  runnableExamples:
    doAssert initTime(1000, 100) - initTime(500, 20) ==
      initDuration(minutes = 8, seconds = 20, nanoseconds = 80)
  subImpl[Duration](a, b)

proc `+`*(a: Time, b: Duration): Time {.operator, extern: "ntAddTime".} =
  ## Add a duration of time to a `Time`.
  runnableExamples:
    doAssert (fromUnix(0) + initDuration(seconds = 1)) == fromUnix(1)
  addImpl[Time](a, b)

proc `-`*(a: Time, b: Duration): Time {.operator, extern: "ntSubTime".} =
  ## Subtracts a duration of time from a `Time`.
  runnableExamples:
    doAssert (fromUnix(0) - initDuration(seconds = 1)) == fromUnix(-1)
  subImpl[Time](a, b)

proc `<`*(a, b: Time): bool {.operator, extern: "ntLtTime".} =
  ## Returns true if `a < b`, that is if `a` happened before `b`.
  runnableExamples:
    doAssert initTime(50, 0) < initTime(99, 0)
  ltImpl(a, b)

proc `<=`*(a, b: Time): bool {.operator, extern: "ntLeTime".} =
  ## Returns true if `a <= b`.
  lqImpl(a, b)

proc `==`*(a, b: Time): bool {.operator, extern: "ntEqTime".} =
  ## Returns true if `a == b`, that is if both times represent the same point in time.
  eqImpl(a, b)

proc `+=`*(t: var Time, b: Duration) =
  t = t + b

proc `-=`*(t: var Time, b: Duration) =
  t = t - b

proc high*(typ: typedesc[Time]): Time =
  initTime(high(int64), high(NanosecondRange))

proc low*(typ: typedesc[Time]): Time =
  initTime(0, 0)

#
# DateTime & Timezone
#

template assertDateTimeInitialized(dt: DateTime) =
  assert dt.monthdayZero != 0, "Uninitialized datetime"

proc nanosecond*(dt: DateTime): NanosecondRange {.inline.} =
  ## The number of nanoseconds after the second,
  ## in the range 0 to 999_999_999.
  assertDateTimeInitialized(dt)
  dt.nanosecond

proc second*(dt: DateTime): SecondRange {.inline.} =
  ## The number of seconds after the minute,
  ## in the range 0 to 59.
  assertDateTimeInitialized(dt)
  dt.second

proc minute*(dt: DateTime): MinuteRange {.inline.} =
  ## The number of minutes after the hour,
  ## in the range 0 to 59.
  assertDateTimeInitialized(dt)
  dt.minute

proc hour*(dt: DateTime): HourRange {.inline.} =
  ## The number of hours past midnight,
  ## in the range 0 to 23.
  assertDateTimeInitialized(dt)
  dt.hour

proc monthday*(dt: DateTime): MonthdayRange {.inline.} =
  ## The day of the month, in the range 1 to 31.
  assertDateTimeInitialized(dt)
  # 'cast' to avoid extra range check
  cast[MonthdayRange](dt.monthdayZero)

proc month*(dt: DateTime): Month =
  ## The month as an enum, the ordinal value
  ## is in the range 1 to 12.
  assertDateTimeInitialized(dt)
  # 'cast' to avoid extra range check
  cast[Month](dt.monthZero)

proc year*(dt: DateTime): int {.inline.} =
  ## The year, using astronomical year numbering
  ## (meaning that before year 1 is year 0,
  ## then year -1 and so on).
  assertDateTimeInitialized(dt)
  dt.year

proc weekday*(dt: DateTime): WeekDay {.inline.} =
  ## The day of the week as an enum, the ordinal
  ## value is in the range 0 (monday) to 6 (sunday).
  assertDateTimeInitialized(dt)
  dt.weekday

proc yearday*(dt: DateTime): YeardayRange {.inline.} =
  ## The number of days since January 1,
  ## in the range 0 to 365.
  assertDateTimeInitialized(dt)
  dt.yearday

proc isDst*(dt: DateTime): bool {.inline.} =
  ## Determines whether DST is in effect.
  ## Always false for the JavaScript backend.
  assertDateTimeInitialized(dt)
  dt.isDst

proc timezone*(dt: DateTime): Timezone {.inline.} =
  ## The timezone represented as an implementation
  ## of `Timezone`.
  assertDateTimeInitialized(dt)
  dt.timezone

proc utcOffset*(dt: DateTime): int {.inline.} =
  ## The offset in seconds west of UTC, including
  ## any offset due to DST. Note that the sign of
  ## this number is the opposite of the one in a
  ## formatted offset string like `+01:00` (which
  ## would be equivalent to the UTC offset
  ## `-3600`).
  assertDateTimeInitialized(dt)
  dt.utcOffset

proc isInitialized(dt: DateTime): bool =
  # Returns true if `dt` is not the (invalid) default value for `DateTime`.
  runnableExamples:
    doAssert now().isInitialized
    doAssert not default(DateTime).isInitialized
  dt.monthZero != 0

since((1, 3)):
  export isInitialized

proc isLeapDay*(dt: DateTime): bool {.since: (1, 1).} =
  ## Returns whether `t` is a leap day, i.e. Feb 29 in a leap year. This matters
  ## as it affects time offset calculations.
  runnableExamples:
    let dt = dateTime(2020, mFeb, 29, 00, 00, 00, 00, utc())
    doAssert dt.isLeapDay
    doAssert dt+1.years-1.years != dt
    let dt2 = dateTime(2020, mFeb, 28, 00, 00, 00, 00, utc())
    doAssert not dt2.isLeapDay
    doAssert dt2+1.years-1.years == dt2
    doAssertRaises(Exception): discard dateTime(2021, mFeb, 29, 00, 00, 00, 00, utc())
  assertDateTimeInitialized dt
  dt.year.isLeapYear and dt.month == mFeb and dt.monthday == 29

proc toTime*(dt: DateTime): Time {.tags: [], raises: [], benign.} =
  ## Converts a `DateTime` to a `Time` representing the same point in time.
  assertDateTimeInitialized dt
  let epochDay = toEpochDay(dt.monthday, dt.month, dt.year)
  var seconds = epochDay * secondsInDay
  seconds.inc dt.hour * secondsInHour
  seconds.inc dt.minute * 60
  seconds.inc dt.second
  seconds.inc dt.utcOffset
  result = initTime(seconds, dt.nanosecond)

proc initDateTime(zt: ZonedTime, zone: Timezone): DateTime =
  ## Create a new `DateTime` using `ZonedTime` in the specified timezone.
  let adjTime = zt.time - initDuration(seconds = zt.utcOffset)
  let s = adjTime.seconds
  let epochday = floorDiv(s, secondsInDay)
  var rem = s - epochday * secondsInDay
  let hour = rem div secondsInHour
  rem = rem - hour * secondsInHour
  let minute = rem div secondsInMin
  rem = rem - minute * secondsInMin
  let second = rem

  let (d, m, y) = fromEpochDay(epochday)

  DateTime(
    year: y,
    monthZero: m.int,
    monthdayZero: d,
    hour: hour,
    minute: minute,
    second: second,
    nanosecond: zt.time.nanosecond,
    weekday: getDayOfWeek(d, m, y),
    yearday: getDayOfYear(d, m, y),
    isDst: zt.isDst,
    timezone: zone,
    utcOffset: zt.utcOffset
  )

proc newTimezone*(
      name: string,
      zonedTimeFromTimeImpl: proc (time: Time): ZonedTime
          {.tags: [], raises: [], benign.},
      zonedTimeFromAdjTimeImpl: proc (adjTime: Time): ZonedTime
          {.tags: [], raises: [], benign.}
    ): owned Timezone =
  ## Create a new `Timezone`.
  ##
  ## `zonedTimeFromTimeImpl` and `zonedTimeFromAdjTimeImpl` is used
  ## as the underlying implementations for `zonedTimeFromTime` and
  ## `zonedTimeFromAdjTime`.
  ##
  ## If possible, the name parameter should match the name used in the
  ## tz database. If the timezone doesn't exist in the tz database, or if the
  ## timezone name is unknown, then any string that describes the timezone
  ## unambiguously can be used. Note that the timezones name is used for
  ## checking equality!
  runnableExamples:
    proc utcTzInfo(time: Time): ZonedTime =
      ZonedTime(utcOffset: 0, isDst: false, time: time)
    let utc = newTimezone("Etc/UTC", utcTzInfo, utcTzInfo)
  Timezone(
    name: name,
    zonedTimeFromTimeImpl: zonedTimeFromTimeImpl,
    zonedTimeFromAdjTimeImpl: zonedTimeFromAdjTimeImpl
  )

proc name*(zone: Timezone): string =
  ## The name of the timezone.
  ##
  ## If possible, the name will be the name used in the tz database.
  ## If the timezone doesn't exist in the tz database, or if the timezone
  ## name is unknown, then any string that describes the timezone
  ## unambiguously might be used. For example, the string "LOCAL" is used
  ## for the system's local timezone.
  ##
  ## See also: https://en.wikipedia.org/wiki/Tz_database
  zone.name

proc zonedTimeFromTime*(zone: Timezone, time: Time): ZonedTime =
  ## Returns the `ZonedTime` for some point in time.
  zone.zonedTimeFromTimeImpl(time)

proc zonedTimeFromAdjTime*(zone: Timezone, adjTime: Time): ZonedTime =
  ## Returns the `ZonedTime` for some local time.
  ##
  ## Note that the `Time` argument does not represent a point in time, it
  ## represent a local time! E.g if `adjTime` is `fromUnix(0)`, it should be
  ## interpreted as 1970-01-01T00:00:00 in the `zone` timezone, not in UTC.
  zone.zonedTimeFromAdjTimeImpl(adjTime)

proc `$`*(zone: Timezone): string =
  ## Returns the name of the timezone.
  if zone != nil: result = zone.name
  else: result = ""

proc `==`*(zone1, zone2: Timezone): bool =
  ## Two `Timezone`'s are considered equal if their name is equal.
  runnableExamples:
    doAssert local() == local()
    doAssert local() != utc()
  if system.`==`(zone1, zone2):
    return true
  if zone1.isNil or zone2.isNil:
    return false
  zone1.name == zone2.name

proc inZone*(time: Time, zone: Timezone): DateTime
    {.tags: [], raises: [], benign.} =
  ## Convert `time` into a `DateTime` using `zone` as the timezone.
  result = initDateTime(zone.zonedTimeFromTime(time), zone)

proc inZone*(dt: DateTime, zone: Timezone): DateTime
    {.tags: [], raises: [], benign.} =
  ## Returns a `DateTime` representing the same point in time as `dt` but
  ## using `zone` as the timezone.
  assertDateTimeInitialized dt
  dt.toTime.inZone(zone)

proc toAdjTime(dt: DateTime): Time =
  let epochDay = toEpochDay(dt.monthday, dt.month, dt.year)
  var seconds = epochDay * secondsInDay
  seconds.inc dt.hour * secondsInHour
  seconds.inc dt.minute * secondsInMin
  seconds.inc dt.second
  result = initTime(seconds, dt.nanosecond)

when defined(js):
  proc localZonedTimeFromTime(time: Time): ZonedTime {.benign.} =
    let jsDate = newDate(time.seconds * 1000)
    let offset = jsDate.getTimezoneOffset() * secondsInMin
    result.time = time
    result.utcOffset = offset
    result.isDst = false

  proc localZonedTimeFromAdjTime(adjTime: Time): ZonedTime {.benign.} =
    let utcDate = newDate(adjTime.seconds * 1000)
    let localDate = newDate(utcDate.getUTCFullYear(), utcDate.getUTCMonth(),
        utcDate.getUTCDate(), utcDate.getUTCHours(), utcDate.getUTCMinutes(),
        utcDate.getUTCSeconds(), 0)

    # This is as dumb as it looks - JS doesn't support years in the range
    # 0-99 in the constructor because they are assumed to be 19xx...
    # Because JS doesn't support timezone history,
    # it doesn't really matter in practice.
    if utcDate.getUTCFullYear() in 0 .. 99:
      localDate.setFullYear(utcDate.getUTCFullYear())

    result.utcOffset = localDate.getTimezoneOffset() * secondsInMin
    result.time = adjTime + initDuration(seconds = result.utcOffset)
    result.isDst = false

else:
  proc toAdjUnix(tm: Tm): int64 =
    let epochDay = toEpochDay(tm.tm_mday, (tm.tm_mon + 1).Month,
                              tm.tm_year.int + 1900)
    result = epochDay * secondsInDay
    result.inc tm.tm_hour * secondsInHour
    result.inc tm.tm_min * 60
    result.inc tm.tm_sec

  proc getLocalOffsetAndDst(unix: int64): tuple[offset: int, dst: bool] =
    # Windows can't handle unix < 0, so we fall back to unix = 0.
    # FIXME: This should be improved by falling back to the WinAPI instead.
    when defined(windows):
      if unix < 0:
        var a = 0.CTime
        let tmPtr = localtime(a)
        if not tmPtr.isNil:
          let tm = tmPtr[]
          return ((0 - tm.toAdjUnix).int, false)
        return (0, false)

    # In case of a 32-bit time_t, we fallback to the closest available
    # timezone information.
    var a = clamp(unix, low(CTime).int64, high(CTime).int64).CTime
    let tmPtr = localtime(a)
    if not tmPtr.isNil:
      let tm = tmPtr[]
      return ((a.int64 - tm.toAdjUnix).int, tm.tm_isdst > 0)
    return (0, false)

  proc localZonedTimeFromTime(time: Time): ZonedTime {.benign.} =
    let (offset, dst) = getLocalOffsetAndDst(time.seconds)
    result = ZonedTime(time: time, utcOffset: offset, isDst: dst)

  proc localZonedTimeFromAdjTime(adjTime: Time): ZonedTime {.benign.} =
    var adjUnix = adjTime.seconds
    let past = adjUnix - secondsInDay
    let (pastOffset, _) = getLocalOffsetAndDst(past)

    let future = adjUnix + secondsInDay
    let (futureOffset, _) = getLocalOffsetAndDst(future)

    var utcOffset: int
    if pastOffset == futureOffset:
      utcOffset = pastOffset.int
    else:
      if pastOffset > futureOffset:
        adjUnix -= secondsInHour

      adjUnix += pastOffset
      utcOffset = getLocalOffsetAndDst(adjUnix).offset

    # This extra roundtrip is needed to normalize any impossible datetimes
    # as a result of offset changes (normally due to dst)
    let utcUnix = adjTime.seconds + utcOffset
    let (finalOffset, dst) = getLocalOffsetAndDst(utcUnix)
    result.time = initTime(utcUnix, adjTime.nanosecond)
    result.utcOffset = finalOffset
    result.isDst = dst

proc utcTzInfo(time: Time): ZonedTime =
  ZonedTime(utcOffset: 0, isDst: false, time: time)

var utcInstance {.threadvar.}: Timezone
var localInstance {.threadvar.}: Timezone

proc utc*(): Timezone =
  ## Get the `Timezone` implementation for the UTC timezone.
  runnableExamples:
    doAssert now().utc.timezone == utc()
    doAssert utc().name == "Etc/UTC"
  if utcInstance.isNil:
    utcInstance = newTimezone("Etc/UTC", utcTzInfo, utcTzInfo)
  result = utcInstance

proc local*(): Timezone =
  ## Get the `Timezone` implementation for the local timezone.
  runnableExamples:
    doAssert now().timezone == local()
    doAssert local().name == "LOCAL"
  if localInstance.isNil:
    localInstance = newTimezone("LOCAL", localZonedTimeFromTime,
      localZonedTimeFromAdjTime)
  result = localInstance

proc utc*(dt: DateTime): DateTime =
  ## Shorthand for `dt.inZone(utc())`.
  dt.inZone(utc())

proc local*(dt: DateTime): DateTime =
  ## Shorthand for `dt.inZone(local())`.
  dt.inZone(local())

proc utc*(t: Time): DateTime =
  ## Shorthand for `t.inZone(utc())`.
  t.inZone(utc())

proc local*(t: Time): DateTime =
  ## Shorthand for `t.inZone(local())`.
  t.inZone(local())

proc now*(): DateTime {.tags: [TimeEffect], benign.} =
  ## Get the current time as a  `DateTime` in the local timezone.
  ## Shorthand for `getTime().local`.
  ##
  ## .. warning:: Unsuitable for benchmarking, use `monotimes.getMonoTime` or
  ##    `cpuTime` instead, depending on the use case.
  getTime().local

proc dateTime*(year: int, month: Month, monthday: MonthdayRange,
               hour: HourRange = 0, minute: MinuteRange = 0, second: SecondRange = 0,
               nanosecond: NanosecondRange = 0,
               zone: Timezone = local()): DateTime =
  ## Create a new `DateTime <#DateTime>`_ in the specified timezone.
  runnableExamples:
    assert $dateTime(2017, mMar, 30, zone = utc()) == "2017-03-30T00:00:00Z"

  assertValidDate monthday, month, year
  let dt = DateTime(
    monthdayZero: monthday,
    year: year,
    monthZero: month.int,
    hour: hour,
    minute: minute,
    second: second,
    nanosecond: nanosecond
  )
  result = initDateTime(zone.zonedTimeFromAdjTime(dt.toAdjTime), zone)

proc initDateTime*(monthday: MonthdayRange, month: Month, year: int,
                   hour: HourRange, minute: MinuteRange, second: SecondRange,
                   nanosecond: NanosecondRange,
                   zone: Timezone = local()): DateTime {.deprecated: "use `dateTime`".} =
  ## Create a new `DateTime <#DateTime>`_ in the specified timezone.
  runnableExamples("--warning:deprecated:off"):
    assert $initDateTime(30, mMar, 2017, 00, 00, 00, 00, utc()) == "2017-03-30T00:00:00Z"
  dateTime(year, month, monthday, hour, minute, second, nanosecond, zone)

proc initDateTime*(monthday: MonthdayRange, month: Month, year: int,
                   hour: HourRange, minute: MinuteRange, second: SecondRange,
                   zone: Timezone = local()): DateTime {.deprecated: "use `dateTime`".} =
  ## Create a new `DateTime <#DateTime>`_ in the specified timezone.
  runnableExamples("--warning:deprecated:off"):
    assert $initDateTime(30, mMar, 2017, 00, 00, 00, utc()) == "2017-03-30T00:00:00Z"
  dateTime(year, month, monthday, hour, minute, second, 0, zone)

proc `+`*(dt: DateTime, dur: Duration): DateTime =
  runnableExamples:
    let dt = dateTime(2017, mMar, 30, 00, 00, 00, 00, utc())
    let dur = initDuration(hours = 5)
    doAssert $(dt + dur) == "2017-03-30T05:00:00Z"

  (dt.toTime + dur).inZone(dt.timezone)

proc `-`*(dt: DateTime, dur: Duration): DateTime =
  runnableExamples:
    let dt = dateTime(2017, mMar, 30, 00, 00, 00, 00, utc())
    let dur = initDuration(days = 5)
    doAssert $(dt - dur) == "2017-03-25T00:00:00Z"

  (dt.toTime - dur).inZone(dt.timezone)

proc `-`*(dt1, dt2: DateTime): Duration =
  ## Compute the duration between `dt1` and `dt2`.
  runnableExamples:
    let dt1 = dateTime(2017, mMar, 30, 00, 00, 00, 00, utc())
    let dt2 = dateTime(2017, mMar, 25, 00, 00, 00, 00, utc())

    doAssert dt1 - dt2 == initDuration(days = 5)

  dt1.toTime - dt2.toTime

proc `<`*(a, b: DateTime): bool =
  ## Returns true if `a` happened before `b`.
  return a.toTime < b.toTime

proc `<=`*(a, b: DateTime): bool =
  ## Returns true if `a` happened before or at the same time as `b`.
  return a.toTime <= b.toTime

proc `==`*(a, b: DateTime): bool =
  ## Returns true if `a` and `b` represent the same point in time.
  if not a.isInitialized: not b.isInitialized
  elif not b.isInitialized: false
  else: a.toTime == b.toTime

proc `+=`*(a: var DateTime, b: Duration) =
  a = a + b

proc `-=`*(a: var DateTime, b: Duration) =
  a = a - b

proc getDateStr*(dt = now()): string {.rtl, extern: "nt$1", tags: [TimeEffect].} =
  ## Gets the current local date as a string of the format `YYYY-MM-dd`.
  runnableExamples:
    echo getDateStr(now() - 1.months)
  assertDateTimeInitialized dt
  result = newStringOfCap(10)  # len("YYYY-MM-dd") == 10
  result.addInt dt.year
  result.add '-'
  result.add intToStr(dt.monthZero, 2)
  result.add '-'
  result.add intToStr(dt.monthday, 2)

proc getClockStr*(dt = now()): string {.rtl, extern: "nt$1", tags: [TimeEffect].} =
  ## Gets the current local clock time as a string of the format `HH:mm:ss`.
  runnableExamples:
    echo getClockStr(now() - 1.hours)
  assertDateTimeInitialized dt
  result = newStringOfCap(8)  # len("HH:mm:ss") == 8
  result.add intToStr(dt.hour, 2)
  result.add ':'
  result.add intToStr(dt.minute, 2)
  result.add ':'
  result.add intToStr(dt.second, 2)


#
# Iso week forward declarations
#

proc initDateTime*(weekday: WeekDay, isoweek: IsoWeekRange, isoyear: IsoYear,
                   hour: HourRange, minute: MinuteRange, second: SecondRange,
                   nanosecond: NanosecondRange,
                   zone: Timezone = local()): DateTime {.gcsafe, raises: [], tags: [], since: (1, 5).}

proc initDateTime*(weekday: WeekDay, isoweek: IsoWeekRange, isoyear: IsoYear,
                   hour: HourRange, minute: MinuteRange, second: SecondRange,
                   zone: Timezone = local()): DateTime {.gcsafe, raises: [], tags: [], since: (1, 5).}

#
# TimeFormat
#

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

type
  DateTimeLocale* = object
    MMM*: array[mJan..mDec, string]
    MMMM*: array[mJan..mDec, string]
    ddd*: array[dMon..dSun, string]
    dddd*: array[dMon..dSun, string]

when defined(nimHasStyleChecks):
  {.pop.}

type
  AmPm = enum
    apUnknown, apAm, apPm

  Era = enum
    eraUnknown, eraAd, eraBc

  ParsedTime = object
    amPm: AmPm
    era: Era
    year: Option[int]
    month: Option[int]
    monthday: Option[int]
    isoyear: Option[int]
    yearweek: Option[int]
    weekday: Option[WeekDay]
    utcOffset: Option[int]

    # '0' as default for these work fine
    # so no need for `Option`.
    hour: int
    minute: int
    second: int
    nanosecond: int

  FormatTokenKind = enum
    tkPattern, tkLiteral

  FormatPattern {.pure.} = enum
    d, dd, ddd, dddd
    GG, GGGG
    h, hh, H, HH
    m, mm, M, MM, MMM, MMMM
    s, ss
    fff, ffffff, fffffffff
    t, tt
    yy, yyyy
    YYYY
    uuuu
    UUUU
    V, VV
    z, zz, zzz, zzzz
    ZZZ, ZZZZ
    g

    # This is a special value used to mark literal format values.
    # See the doc comment for `TimeFormat.patterns`.
    Lit

  TimeFormat* = object  ## Represents a format for parsing and printing
                        ## time types.
                        ##
                        ## To create a new `TimeFormat` use `initTimeFormat proc
                        ## <#initTimeFormat,string>`_.
    patterns: seq[byte] ## \
      ## Contains the patterns encoded as bytes.
      ## Literal values are encoded in a special way.
      ## They start with `Lit.byte`, then the length of the literal, then the
      ## raw char values of the literal. For example, the literal `foo` would
      ## be encoded as `@[Lit.byte, 3.byte, 'f'.byte, 'o'.byte, 'o'.byte]`.
    formatStr: string

  TimeParseError* = object of ValueError ## \
    ## Raised when parsing input using a `TimeFormat` fails.

  TimeFormatParseError* = object of ValueError ## \
    ## Raised when parsing a `TimeFormat` string fails.

const
  DefaultLocale* = DateTimeLocale(
    MMM: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
        "Nov", "Dec"],
    MMMM: ["January", "February", "March", "April", "May", "June", "July",
        "August", "September", "October", "November", "December"],
    ddd: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    dddd: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
        "Sunday"],
  )

  FormatLiterals = {' ', '-', '/', ':', '(', ')', '[', ']', ',', '.'}

proc `$`*(f: TimeFormat): string =
  ## Returns the format string that was used to construct `f`.
  runnableExamples:
    let f = initTimeFormat("yyyy-MM-dd")
    doAssert $f == "yyyy-MM-dd"
  f.formatStr

proc raiseParseException(f: TimeFormat, input: string, msg: string) =
  raise newException(TimeParseError,
                     "Failed to parse '" & input & "' with format '" & $f &
                     "'. " & msg)

proc parseInt(s: string, b: var int, start = 0, maxLen = int.high,
              allowSign = false): int =
  var sign = -1
  var i = start
  let stop = start + min(s.high - start + 1, maxLen) - 1
  if allowSign and i <= stop:
    if s[i] == '+':
      inc(i)
    elif s[i] == '-':
      inc(i)
      sign = 1
  if i <= stop and s[i] in {'0'..'9'}:
    b = 0
    while i <= stop and s[i] in {'0'..'9'}:
      let c = ord(s[i]) - ord('0')
      if b >= (low(int) + c) div 10:
        b = b * 10 - c
      else:
        return 0
      inc(i)
    if sign == -1 and b == low(int):
      return 0
    b = b * sign
    result = i - start
  else:
    result = 0

iterator tokens(f: string): tuple[kind: FormatTokenKind, token: string] =
  var i = 0
  var currToken = ""

  template yieldCurrToken() =
    if currToken.len != 0:
      yield (tkPattern, currToken)
      currToken = ""

  while i < f.len:
    case f[i]
    of '\'':
      yieldCurrToken()
      if i.succ < f.len and f[i.succ] == '\'':
        yield (tkLiteral, "'")
        i.inc 2
      else:
        var token = ""
        inc(i) # Skip '
        while i < f.len and f[i] != '\'':
          token.add f[i]
          i.inc

        if i > f.high:
          raise newException(TimeFormatParseError,
                             "Unclosed ' in time format string. " &
                             "For a literal ', use ''.")
        i.inc
        yield (tkLiteral, token)
    of FormatLiterals:
      yieldCurrToken()
      yield (tkLiteral, $f[i])
      i.inc
    else:
      # Check if the letter being added matches previous accumulated buffer.
      if currToken.len == 0 or currToken[0] == f[i]:
        currToken.add(f[i])
        i.inc
      else:
        yield (tkPattern, currToken)
        currToken = $f[i]
        i.inc

  yieldCurrToken()

proc stringToPattern(str: string): FormatPattern =
  case str
  of "d": result = d
  of "dd": result = dd
  of "ddd": result = ddd
  of "dddd": result = dddd
  of "GG": result = GG
  of "GGGG": result = GGGG
  of "h": result = h
  of "hh": result = hh
  of "H": result = H
  of "HH": result = HH
  of "m": result = m
  of "mm": result = mm
  of "M": result = M
  of "MM": result = MM
  of "MMM": result = MMM
  of "MMMM": result = MMMM
  of "s": result = s
  of "ss": result = ss
  of "fff": result = fff
  of "ffffff": result = ffffff
  of "fffffffff": result = fffffffff
  of "t": result = t
  of "tt": result = tt
  of "yy": result = yy
  of "yyyy": result = yyyy
  of "YYYY": result = YYYY
  of "uuuu": result = uuuu
  of "UUUU": result = UUUU
  of "V": result = V
  of "VV": result = VV
  of "z": result = z
  of "zz": result = zz
  of "zzz": result = zzz
  of "zzzz": result = zzzz
  of "ZZZ": result = ZZZ
  of "ZZZZ": result = ZZZZ
  of "g": result = g
  else: raise newException(TimeFormatParseError,
                           "'" & str & "' is not a valid pattern")

proc initTimeFormat*(format: string): TimeFormat =
  ## Construct a new time format for parsing & formatting time types.
  ##
  ## See `Parsing and formatting dates`_ for documentation of the
  ## `format` argument.
  runnableExamples:
    let f = initTimeFormat("yyyy-MM-dd")
    doAssert "2000-01-01" == "2000-01-01".parse(f).format(f)
  result = TimeFormat(formatStr: format, patterns: @[])
  for kind, token in format.tokens:
    case kind
    of tkLiteral:
      case token
      else:
        result.patterns.add(FormatPattern.Lit.byte)
        if token.len > 255:
          raise newException(TimeFormatParseError,
                             "Format literal is to long:" & token)
        result.patterns.add(token.len.byte)
        for c in token:
          result.patterns.add(c.byte)
    of tkPattern:
      result.patterns.add(stringToPattern(token).byte)

proc formatPattern(dt: DateTime, pattern: FormatPattern, result: var string,
    loc: DateTimeLocale) =
  template yearOfEra(dt: DateTime): int =
    if dt.year <= 0: abs(dt.year) + 1 else: dt.year

  case pattern
  of d:
    result.add $dt.monthday
  of dd:
    result.add dt.monthday.intToStr(2)
  of ddd:
    result.add loc.ddd[dt.weekday]
  of dddd:
    result.add loc.dddd[dt.weekday]
  of GG:
    result.add (dt.getIsoWeekAndYear.isoyear.int mod 100).intToStr(2)
  of GGGG:
    result.add $dt.getIsoWeekAndYear.isoyear
  of h:
    result.add(
      if dt.hour == 0: "12"
      elif dt.hour > 12: $(dt.hour - 12)
      else: $dt.hour
    )
  of hh:
    result.add(
      if dt.hour == 0: "12"
      elif dt.hour > 12: (dt.hour - 12).intToStr(2)
      else: dt.hour.intToStr(2)
    )
  of H:
    result.add $dt.hour
  of HH:
    result.add dt.hour.intToStr(2)
  of m:
    result.add $dt.minute
  of mm:
    result.add dt.minute.intToStr(2)
  of M:
    result.add $ord(dt.month)
  of MM:
    result.add ord(dt.month).intToStr(2)
  of MMM:
    result.add loc.MMM[dt.month]
  of MMMM:
    result.add loc.MMMM[dt.month]
  of s:
    result.add $dt.second
  of ss:
    result.add dt.second.intToStr(2)
  of fff:
    result.add(intToStr(convert(Nanoseconds, Milliseconds, dt.nanosecond), 3))
  of ffffff:
    result.add(intToStr(convert(Nanoseconds, Microseconds, dt.nanosecond), 6))
  of fffffffff:
    result.add(intToStr(dt.nanosecond, 9))
  of t:
    result.add if dt.hour >= 12: "P" else: "A"
  of tt:
    result.add if dt.hour >= 12: "PM" else: "AM"
  of yy:
    result.add (dt.yearOfEra mod 100).intToStr(2)
  of yyyy:
    let year = dt.yearOfEra
    if year < 10000:
      result.add year.intToStr(4)
    else:
      result.add '+' & $year
  of YYYY:
    if dt.year < 1:
      result.add $(abs(dt.year) + 1)
    else:
      result.add $dt.year
  of uuuu:
    let year = dt.year
    if year < 10000 or year < 0:
      result.add year.intToStr(4)
    else:
      result.add '+' & $year
  of UUUU:
    result.add $dt.year
  of V:
    result.add $dt.getIsoWeekAndYear.isoweek
  of VV:
    result.add dt.getIsoWeekAndYear.isoweek.intToStr(2)
  of z, zz, zzz, zzzz, ZZZ, ZZZZ:
    if dt.timezone != nil and dt.timezone.name == "Etc/UTC":
      result.add 'Z'
    else:
      result.add if -dt.utcOffset >= 0: '+' else: '-'
      let absOffset = abs(dt.utcOffset)
      case pattern:
      of z:
        result.add $(absOffset div 3600)
      of zz:
        result.add (absOffset div 3600).intToStr(2)
      of zzz, ZZZ:
        let h = (absOffset div 3600).intToStr(2)
        let m = ((absOffset div 60) mod 60).intToStr(2)
        let sep = if pattern == zzz: ":" else: ""
        result.add h & sep & m
      of zzzz, ZZZZ:
        let absOffset = abs(dt.utcOffset)
        let h = (absOffset div 3600).intToStr(2)
        let m = ((absOffset div 60) mod 60).intToStr(2)
        let s = (absOffset mod 60).intToStr(2)
        let sep = if pattern == zzzz: ":" else: ""
        result.add h & sep & m & sep & s
      else: assert false
  of g:
    result.add if dt.year < 1: "BC" else: "AD"
  of Lit: assert false # Can't happen

proc parsePattern(input: string, pattern: FormatPattern, i: var int,
                  parsed: var ParsedTime, loc: DateTimeLocale): bool =
  template takeInt(allowedWidth: Slice[int], allowSign = false): int =
    var sv = 0
    var pd = parseInt(input, sv, i, allowedWidth.b, allowSign)
    if pd < allowedWidth.a:
      return false
    i.inc pd
    sv

  template contains[T](t: typedesc[T], i: int): bool =
    i in low(t)..high(t)

  result = true

  case pattern
  of d:
    let monthday = takeInt(1..2)
    parsed.monthday = some(monthday)
    result = monthday in MonthdayRange
  of dd:
    let monthday = takeInt(2..2)
    parsed.monthday = some(monthday)
    result = monthday in MonthdayRange
  of ddd:
    result = false
    for d, v in loc.ddd:
      if input.substr(i, i+v.len-1).cmpIgnoreCase(v) == 0:
        parsed.weekday = some(d.WeekDay)
        result = true
        i.inc v.len
        break
  of dddd:
    result = false
    for d, v in loc.dddd:
      if input.substr(i, i+v.len-1).cmpIgnoreCase(v) == 0:
        parsed.weekday = some(d.WeekDay)
        result = true
        i.inc v.len
        break
  of GG:
    # Assumes current century
    var isoyear = takeInt(2..2)
    var thisCen = now().year div 100
    parsed.isoyear = some(thisCen*100 + isoyear)
    result = isoyear > 0
  of GGGG:
    let isoyear = takeInt(1..high(int))
    parsed.isoyear = some(isoyear)
    result = isoyear > 0
  of h, H:
    parsed.hour = takeInt(1..2)
    result = parsed.hour in HourRange
  of hh, HH:
    parsed.hour = takeInt(2..2)
    result = parsed.hour in HourRange
  of m:
    parsed.minute = takeInt(1..2)
    result = parsed.hour in MinuteRange
  of mm:
    parsed.minute = takeInt(2..2)
    result = parsed.hour in MinuteRange
  of M:
    let month = takeInt(1..2)
    result = month in 1..12
    parsed.month = some(month)
  of MM:
    let month = takeInt(2..2)
    result = month in 1..12
    parsed.month = some(month)
  of MMM:
    result = false
    for n, v in loc.MMM:
      if input.substr(i, i+v.len-1).cmpIgnoreCase(v) == 0:
        result = true
        i.inc v.len
        parsed.month = some(n.int)
        break
  of MMMM:
    result = false
    for n, v in loc.MMMM:
      if input.substr(i, i+v.len-1).cmpIgnoreCase(v) == 0:
        result = true
        i.inc v.len
        parsed.month = some(n.int)
        break
  of s:
    parsed.second = takeInt(1..2)
  of ss:
    parsed.second = takeInt(2..2)
  of fff, ffffff, fffffffff:
    let len = ($pattern).len
    let v = takeInt(len..len)
    parsed.nanosecond = v * 10^(9 - len)
    result = parsed.nanosecond in NanosecondRange
  of t:
    case input[i]:
    of 'P':
      parsed.amPm = apPm
    of 'A':
      parsed.amPm = apAm
    else:
      result = false
    i.inc 1
  of tt:
    if input.substr(i, i+1).cmpIgnoreCase("AM") == 0:
      parsed.amPm = apAm
      i.inc 2
    elif input.substr(i, i+1).cmpIgnoreCase("PM") == 0:
      parsed.amPm = apPm
      i.inc 2
    else:
      result = false
  of yy:
    # Assumes current century
    var year = takeInt(2..2)
    var thisCen = now().year div 100
    parsed.year = some(thisCen*100 + year)
    result = year > 0
  of yyyy:
    let year =
      if input[i] in {'+', '-'}:
        takeInt(4..high(int), allowSign = true)
      else:
        takeInt(4..4)
    result = year > 0
    parsed.year = some(year)
  of YYYY:
    let year = takeInt(1..high(int))
    parsed.year = some(year)
    result = year > 0
  of uuuu:
    let year =
      if input[i] in {'+', '-'}:
        takeInt(4..high(int), allowSign = true)
      else:
        takeInt(4..4)
    parsed.year = some(year)
  of UUUU:
    parsed.year = some(takeInt(1..high(int), allowSign = true))
  of V:
    let yearweek = takeInt(1..2)
    parsed.yearweek = some(yearweek)
    result = yearweek in IsoWeekRange
  of VV:
    let yearweek = takeInt(2..2)
    parsed.yearweek = some(yearweek)
    result = yearweek in IsoWeekRange
  of z, zz, zzz, zzzz, ZZZ, ZZZZ:
    case input[i]
    of '+', '-':
      let sign = if input[i] == '-': 1 else: -1
      i.inc
      var offset = 0
      case pattern
      of z:
        offset = takeInt(1..2) * 3600
      of zz:
        offset = takeInt(2..2) * 3600
      of zzz, ZZZ:
        offset.inc takeInt(2..2) * 3600
        if pattern == zzz:
          if input[i] != ':':
            return false
          i.inc
        offset.inc takeInt(2..2) * 60
      of zzzz, ZZZZ:
        offset.inc takeInt(2..2) * 3600
        if pattern == zzzz:
          if input[i] != ':':
            return false
          i.inc
        offset.inc takeInt(2..2) * 60
        if pattern == zzzz:
          if input[i] != ':':
            return false
          i.inc
        offset.inc takeInt(2..2)
      else: assert false
      parsed.utcOffset = some(offset * sign)
    of 'Z':
      parsed.utcOffset = some(0)
      i.inc
    else:
      result = false
  of g:
    if input.substr(i, i+1).cmpIgnoreCase("BC") == 0:
      parsed.era = eraBc
      i.inc 2
    elif input.substr(i, i+1).cmpIgnoreCase("AD") == 0:
      parsed.era = eraAd
      i.inc 2
    else:
      result = false
  of Lit: raiseAssert "Can't happen"

proc toDateTime(p: ParsedTime, zone: Timezone, f: TimeFormat,
                input: string): DateTime =
  var year = p.year.get(0)
  var month = p.month.get(1).Month
  var monthday = p.monthday.get(1)
  year =
    case p.era
    of eraUnknown:
      year
    of eraBc:
      if year < 1:
        raiseParseException(f, input,
          "Expected year to be positive " &
          "(use 'UUUU' or 'uuuu' for negative years).")
      -year + 1
    of eraAd:
      if year < 1:
        raiseParseException(f, input,
          "Expected year to be positive " &
          "(use 'UUUU' or 'uuuu' for negative years).")
      year

  let hour =
    case p.amPm
    of apUnknown:
      p.hour
    of apAm:
      if p.hour notin 1..12:
        raiseParseException(f, input,
          "AM/PM time must be in the interval 1..12")
      if p.hour == 12: 0 else: p.hour
    of apPm:
      if p.hour notin 1..12:
        raiseParseException(f, input,
          "AM/PM time must be in the interval 1..12")
      if p.hour == 12: p.hour else: p.hour + 12
  let minute = p.minute
  let second = p.second
  let nanosecond = p.nanosecond

  if monthday > getDaysInMonth(month, year):
    raiseParseException(f, input,
      $year & "-" & ord(month).intToStr(2) &
      "-" & $monthday & " is not a valid date")

  if p.utcOffset.isNone:
    # No timezone parsed - assume timezone is `zone`
    result = dateTime(year, month, monthday, hour, minute, second, nanosecond, zone)
  else:
    # Otherwise convert to `zone`
    result = (dateTime(year, month, monthday, hour, minute, second, nanosecond, utc()).toTime +
      initDuration(seconds = p.utcOffset.get())).inZone(zone)

proc toDateTimeByWeek(p: ParsedTime, zone: Timezone, f: TimeFormat,
                   input: string): DateTime =
  var isoyear = p.isoyear.get(0)
  var yearweek = p.yearweek.get(1)
  var weekday = p.weekday.get(dMon)

  if p.amPm != apUnknown:
    raiseParseException(f, input, "Parsing iso weekyear dates does not support am/pm")

  if p.year.isSome:
    raiseParseException(f, input, "Use iso-year GG or GGGG as year with iso week number")

  if p.month.isSome:
    raiseParseException(f, input, "Use either iso week number V or VV or month")

  if p.monthday.isSome:
    raiseParseException(f, input, "Use weekday ddd or dddd as day with with iso week number")

  if p.isoyear.isNone:
    raiseParseException(f, input, "Need iso-year with week number")

  let hour = p.hour
  let minute = p.minute
  let second = p.second
  let nanosecond = p.nanosecond

  if p.utcOffset.isNone:
    result = initDateTime(weekday, yearweek.IsoWeekRange, isoyear.IsoYear, hour, minute, second, nanosecond, zone)
  else:
    result = (initDateTime(weekday, yearweek.IsoWeekRange, isoyear.IsoYear, hour, minute, second, nanosecond, zone).toTime +
      initDuration(seconds = p.utcOffset.get())).inZone(zone)

proc format*(dt: DateTime, f: TimeFormat,
    loc: DateTimeLocale = DefaultLocale): string {.raises: [].} =
  ## Format `dt` using the format specified by `f`.
  runnableExamples:
    let f = initTimeFormat("yyyy-MM-dd")
    let dt = dateTime(2000, mJan, 01, 00, 00, 00, 00, utc())
    doAssert "2000-01-01" == dt.format(f)
  assertDateTimeInitialized dt
  result = ""
  var idx = 0
  while idx <= f.patterns.high:
    case f.patterns[idx].FormatPattern
    of Lit:
      idx.inc
      let len = f.patterns[idx]
      for i in 1'u8..len:
        idx.inc
        result.add f.patterns[idx].char
      idx.inc
    else:
      formatPattern(dt, f.patterns[idx].FormatPattern, result = result, loc = loc)
      idx.inc

proc format*(dt: DateTime, f: string, loc: DateTimeLocale = DefaultLocale): string
    {.raises: [TimeFormatParseError].} =
  ## Shorthand for constructing a `TimeFormat` and using it to format `dt`.
  ##
  ## See `Parsing and formatting dates`_ for documentation of the
  ## `format` argument.
  runnableExamples:
    let dt = dateTime(2000, mJan, 01, 00, 00, 00, 00, utc())
    doAssert "2000-01-01" == format(dt, "yyyy-MM-dd")
  let dtFormat = initTimeFormat(f)
  result = dt.format(dtFormat, loc)

proc format*(dt: DateTime, f: static[string]): string {.raises: [].} =
  ## Overload that validates `format` at compile time.
  const f2 = initTimeFormat(f)
  result = dt.format(f2)

proc formatValue*(result: var string; value: DateTime | Time, specifier: string) =
  ## adapter for strformat. Not intended to be called directly.
  result.add format(value,
    if specifier.len == 0: "yyyy-MM-dd'T'HH:mm:sszzz" else: specifier)

proc format*(time: Time, f: string, zone: Timezone = local()): string
    {.raises: [TimeFormatParseError].} =
  ## Shorthand for constructing a `TimeFormat` and using it to format
  ## `time`. Will use the timezone specified by `zone`.
  ##
  ## See `Parsing and formatting dates`_ for documentation of the
  ## `f` argument.
  runnableExamples:
    var dt = dateTime(1970, mJan, 01, 00, 00, 00, 00, utc())
    var tm = dt.toTime()
    doAssert format(tm, "yyyy-MM-dd'T'HH:mm:ss", utc()) == "1970-01-01T00:00:00"
  time.inZone(zone).format(f)

proc format*(time: Time, f: static[string], zone: Timezone = local()): string
    {.raises: [].} =
  ## Overload that validates `f` at compile time.
  const f2 = initTimeFormat(f)
  result = time.inZone(zone).format(f2)

proc parse*(input: string, f: TimeFormat, zone: Timezone = local(),
    loc: DateTimeLocale = DefaultLocale): DateTime {.parseRaises.} =
  ## Parses `input` as a `DateTime` using the format specified by `f`.
  ## If no UTC offset was parsed, then `input` is assumed to be specified in
  ## the `zone` timezone. If a UTC offset was parsed, the result will be
  ## converted to the `zone` timezone.
  ##
  ## Month and day names from the passed in `loc` are used.
  runnableExamples:
    let f = initTimeFormat("yyyy-MM-dd")
    let dt = dateTime(2000, mJan, 01, 00, 00, 00, 00, utc())
    doAssert dt == "2000-01-01".parse(f, utc())
  var inpIdx = 0 # Input index
  var patIdx = 0 # Pattern index
  var parsed: ParsedTime
  while inpIdx <= input.high and patIdx <= f.patterns.high:
    let pattern = f.patterns[patIdx].FormatPattern
    case pattern
    of Lit:
      patIdx.inc
      let len = f.patterns[patIdx]
      patIdx.inc
      for _ in 1'u8..len:
        if input[inpIdx] != f.patterns[patIdx].char:
          raiseParseException(f, input,
                              "Unexpected character: " & input[inpIdx])
        inpIdx.inc
        patIdx.inc
    else:
      if not parsePattern(input, pattern, inpIdx, parsed, loc):
        raiseParseException(f, input, "Failed on pattern '" & $pattern & "'")
      patIdx.inc

  if inpIdx <= input.high:
    raiseParseException(f, input,
                        "Parsing ended but there was still input remaining")

  if patIdx <= f.patterns.high:
    raiseParseException(f, input,
                            "Parsing ended but there was still patterns remaining")

  if parsed.yearweek.isSome:
    result = toDateTimeByWeek(parsed, zone, f, input)
  elif parsed.isoyear.isSome:
    raiseParseException(f, input, "Iso year GG or GGGG require iso week V or VV")
  else:
    result = toDateTime(parsed, zone, f, input)

proc parse*(input, f: string, tz: Timezone = local(),
    loc: DateTimeLocale = DefaultLocale): DateTime {.parseFormatRaises.} =
  ## Shorthand for constructing a `TimeFormat` and using it to parse
  ## `input` as a `DateTime`.
  ##
  ## See `Parsing and formatting dates`_ for documentation of the
  ## `f` argument.
  runnableExamples:
    let dt = dateTime(2000, mJan, 01, 00, 00, 00, 00, utc())
    doAssert dt == parse("2000-01-01", "yyyy-MM-dd", utc())
  let dtFormat = initTimeFormat(f)
  result = input.parse(dtFormat, tz, loc = loc)

proc parse*(input: string, f: static[string], zone: Timezone = local(),
    loc: DateTimeLocale = DefaultLocale): DateTime {.parseRaises.} =
  ## Overload that validates `f` at compile time.
  const f2 = initTimeFormat(f)
  result = input.parse(f2, zone, loc = loc)

proc parseTime*(input, f: string, zone: Timezone): Time {.parseFormatRaises.} =
  ## Shorthand for constructing a `TimeFormat` and using it to parse
  ## `input` as a `DateTime`, then converting it a `Time`.
  ##
  ## See `Parsing and formatting dates`_ for documentation of the
  ## `format` argument.
  runnableExamples:
    let tStr = "1970-01-01T00:00:00+00:00"
    doAssert parseTime(tStr, "yyyy-MM-dd'T'HH:mm:sszzz", utc()) == fromUnix(0)
  parse(input, f, zone).toTime()

proc parseTime*(input: string, f: static[string], zone: Timezone): Time
    {.parseRaises.} =
  ## Overload that validates `format` at compile time.
  const f2 = initTimeFormat(f)
  result = input.parse(f2, zone).toTime()

proc `$`*(dt: DateTime): string {.tags: [], raises: [], benign.} =
  ## Converts a `DateTime` object to a string representation.
  ## It uses the format `yyyy-MM-dd'T'HH:mm:sszzz`.
  runnableExamples:
    let dt = dateTime(2000, mJan, 01, 12, 00, 00, 00, utc())
    doAssert $dt == "2000-01-01T12:00:00Z"
    doAssert $default(DateTime) == "Uninitialized DateTime"
  if not dt.isInitialized:
    result = "Uninitialized DateTime"
  else:
    result = format(dt, "yyyy-MM-dd'T'HH:mm:sszzz")

proc `$`*(time: Time): string {.tags: [], raises: [], benign.} =
  ## Converts a `Time` value to a string representation. It will use the local
  ## time zone and use the format `yyyy-MM-dd'T'HH:mm:sszzz`.
  runnableExamples:
    let dt = dateTime(1970, mJan, 01, 00, 00, 00, 00, local())
    let tm = dt.toTime()
    doAssert $tm == "1970-01-01T00:00:00" & format(dt, "zzz")
  $time.local

#
# TimeInterval
#

proc initTimeInterval*(nanoseconds, microseconds, milliseconds,
                       seconds, minutes, hours,
                       days, weeks, months, years: int = 0): TimeInterval =
  ## Creates a new `TimeInterval <#TimeInterval>`_.
  ##
  ## This proc doesn't perform any normalization! For example,
  ## `initTimeInterval(hours = 24)` and `initTimeInterval(days = 1)` are
  ## not equal.
  ##
  ## You can also use the convenience procedures called `milliseconds`,
  ## `seconds`, `minutes`, `hours`, `days`, `months`, and `years`.
  runnableExamples:
    let day = initTimeInterval(hours = 24)
    let dt = dateTime(2000, mJan, 01, 12, 00, 00, 00, utc())
    doAssert $(dt + day) == "2000-01-02T12:00:00Z"
    doAssert initTimeInterval(hours = 24) != initTimeInterval(days = 1)
  result = TimeInterval(
    nanoseconds: nanoseconds,
    microseconds: microseconds,
    milliseconds: milliseconds,
    seconds: seconds,
    minutes: minutes,
    hours: hours,
    days: days,
    weeks: weeks,
    months: months,
    years: years
  )

proc `+`*(ti1, ti2: TimeInterval): TimeInterval =
  ## Adds two `TimeInterval` objects together.
  result = TimeInterval(
    nanoseconds: ti1.nanoseconds + ti2.nanoseconds,
    microseconds: ti1.microseconds + ti2.microseconds,
    milliseconds: ti1.milliseconds + ti2.milliseconds,
    seconds: ti1.seconds + ti2.seconds,
    minutes: ti1.minutes + ti2.minutes,
    hours: ti1.hours + ti2.hours,
    days: ti1.days + ti2.days,
    weeks: ti1.weeks + ti2.weeks,
    months: ti1.months + ti2.months,
    years: ti1.years + ti2.years
  )

proc `-`*(ti: TimeInterval): TimeInterval =
  ## Reverses a time interval
  runnableExamples:
    let day = -initTimeInterval(hours = 24)
    doAssert day.hours == -24

  result = TimeInterval(
    nanoseconds: -ti.nanoseconds,
    microseconds: -ti.microseconds,
    milliseconds: -ti.milliseconds,
    seconds: -ti.seconds,
    minutes: -ti.minutes,
    hours: -ti.hours,
    days: -ti.days,
    weeks: -ti.weeks,
    months: -ti.months,
    years: -ti.years
  )

proc `-`*(ti1, ti2: TimeInterval): TimeInterval =
  ## Subtracts TimeInterval `ti1` from `ti2`.
  ##
  ## Time components are subtracted one-by-one, see output:
  runnableExamples:
    let ti1 = initTimeInterval(hours = 24)
    let ti2 = initTimeInterval(hours = 4)
    doAssert (ti1 - ti2) == initTimeInterval(hours = 20)

  result = ti1 + (-ti2)

proc `+=`*(a: var TimeInterval, b: TimeInterval) =
  a = a + b

proc `-=`*(a: var TimeInterval, b: TimeInterval) =
  a = a - b

proc isStaticInterval(interval: TimeInterval): bool =
  interval.years == 0 and interval.months == 0 and
    interval.days == 0 and interval.weeks == 0

proc evaluateStaticInterval(interval: TimeInterval): Duration =
  assert interval.isStaticInterval
  initDuration(nanoseconds = interval.nanoseconds,
    microseconds = interval.microseconds,
    milliseconds = interval.milliseconds,
    seconds = interval.seconds,
    minutes = interval.minutes,
    hours = interval.hours)

proc between*(startDt, endDt: DateTime): TimeInterval =
  ## Gives the difference between `startDt` and `endDt` as a
  ## `TimeInterval`. The following guarantees about the result is given:
  ##
  ## - All fields will have the same sign.
  ## - If `startDt.timezone == endDt.timezone`, it is guaranteed that
  ##   `startDt + between(startDt, endDt) == endDt`.
  ## - If `startDt.timezone != endDt.timezone`, then the result will be
  ##   equivalent to `between(startDt.utc, endDt.utc)`.
  runnableExamples:
    var a = dateTime(2015, mMar, 25, 12, 0, 0, 00, utc())
    var b = dateTime(2017, mApr, 1, 15, 0, 15, 00, utc())
    var ti = initTimeInterval(years = 2, weeks = 1, hours = 3, seconds = 15)
    doAssert between(a, b) == ti
    doAssert between(a, b) == -between(b, a)

  result = default(TimeInterval)
  if startDt.timezone != endDt.timezone:
    return between(startDt.utc, endDt.utc)
  elif endDt < startDt:
    return -between(endDt, startDt)

  type Date = tuple[year, month, monthday: int]
  var startDate: Date = (startDt.year, startDt.month.ord, startDt.monthday)
  var endDate: Date = (endDt.year, endDt.month.ord, endDt.monthday)

  # Subtract one day from endDate if time of day is earlier than startDay
  # The subtracted day will be counted by fixed units (hour and lower)
  # at the end of this proc
  if (endDt.hour, endDt.minute, endDt.second, endDt.nanosecond) <
      (startDt.hour, startDt.minute, startDt.second, startDt.nanosecond):
    if endDate.month == 1 and endDate.monthday == 1:
      endDate.year.dec
      endDate.monthday = 31
      endDate.month = 12
    elif endDate.monthday == 1:
      endDate.month.dec
      endDate.monthday = getDaysInMonth(endDate.month.Month, endDate.year)
    else:
      endDate.monthday.dec

  # Years
  result.years = endDate.year - startDate.year - 1
  if (startDate.month, startDate.monthday) <= (endDate.month, endDate.monthday):
    result.years.inc
  startDate.year.inc result.years

  # Months
  if startDate.year < endDate.year:
    result.months.inc 12 - startDate.month # Move to dec
    if endDate.month != 1 or (startDate.monthday <= endDate.monthday):
      result.months.inc
      startDate.year = endDate.year
      startDate.month = 1
    else:
      startDate.month = 12
  if startDate.year == endDate.year:
    if (startDate.monthday <= endDate.monthday):
      result.months.inc endDate.month - startDate.month
      startDate.month = endDate.month
    elif endDate.month != 1:
      let month = endDate.month - 1
      let daysInMonth = getDaysInMonth(month.Month, startDate.year)
      if daysInMonth < startDate.monthday:
        if startDate.monthday - daysInMonth < endDate.monthday:
          result.months.inc endDate.month - startDate.month - 1
          startDate.month = endDate.month
          startDate.monthday = startDate.monthday - daysInMonth
        else:
          result.months.inc endDate.month - startDate.month - 2
          startDate.month = endDate.month - 2
      else:
        result.months.inc endDate.month - startDate.month - 1
        startDate.month = endDate.month - 1

  # Days
  # This means that start = dec and end = jan
  if startDate.year < endDate.year:
    result.days.inc 31 - startDate.monthday + endDate.monthday
    startDate = endDate
  else:
    while startDate.month < endDate.month:
      let daysInMonth = getDaysInMonth(startDate.month.Month, startDate.year)
      result.days.inc daysInMonth - startDate.monthday + 1
      startDate.month.inc
      startDate.monthday = 1
    result.days.inc endDate.monthday - startDate.monthday
    result.weeks = result.days div 7
    result.days = result.days mod 7
    startDate = endDate

  # Handle hours, minutes, seconds, milliseconds, microseconds and nanoseconds
  let newStartDt = dateTime(startDate.year, startDate.month.Month,
    startDate.monthday, startDt.hour, startDt.minute, startDt.second,
    startDt.nanosecond, startDt.timezone)
  let dur = endDt - newStartDt
  let parts = toParts(dur)
  # There can still be a full day in `parts` since `Duration` and `TimeInterval`
  # models days differently.
  result.hours = parts[Hours].int + parts[Days].int * 24
  result.minutes = parts[Minutes].int
  result.seconds = parts[Seconds].int
  result.milliseconds = parts[Milliseconds].int
  result.microseconds = parts[Microseconds].int
  result.nanoseconds = parts[Nanoseconds].int

proc toParts*(ti: TimeInterval): TimeIntervalParts =
  ## Converts a `TimeInterval` into an array consisting of its time units,
  ## starting with nanoseconds and ending with years.
  ##
  ## This procedure is useful for converting `TimeInterval` values to strings.
  ## E.g. then you need to implement custom interval printing
  runnableExamples:
    var tp = toParts(initTimeInterval(years = 1, nanoseconds = 123))
    doAssert tp[Years] == 1
    doAssert tp[Nanoseconds] == 123
  result = default(TimeIntervalParts)
  var index = 0
  for name, value in fieldPairs(ti):
    result[index.TimeUnit()] = value
    index += 1

proc `$`*(ti: TimeInterval): string =
  ## Get string representation of `TimeInterval`.
  runnableExamples:
    doAssert $initTimeInterval(years = 1, nanoseconds = 123) ==
      "1 year and 123 nanoseconds"
    doAssert $initTimeInterval() == "0 nanoseconds"

  var parts: seq[string] = @[]
  var tiParts = toParts(ti)
  for unit in countdown(Years, Nanoseconds):
    if tiParts[unit] != 0:
      parts.add(stringifyUnit(tiParts[unit], unit))

  result = humanizeParts(parts)

proc nanoseconds*(nanos: int): TimeInterval {.inline.} =
  ## TimeInterval of `nanos` nanoseconds.
  initTimeInterval(nanoseconds = nanos)

proc microseconds*(micros: int): TimeInterval {.inline.} =
  ## TimeInterval of `micros` microseconds.
  initTimeInterval(microseconds = micros)

proc milliseconds*(ms: int): TimeInterval {.inline.} =
  ## TimeInterval of `ms` milliseconds.
  initTimeInterval(milliseconds = ms)

proc seconds*(s: int): TimeInterval {.inline.} =
  ## TimeInterval of `s` seconds.
  ##
  ## `echo getTime() + 5.seconds`
  initTimeInterval(seconds = s)

proc minutes*(m: int): TimeInterval {.inline.} =
  ## TimeInterval of `m` minutes.
  ##
  ## `echo getTime() + 5.minutes`
  initTimeInterval(minutes = m)

proc hours*(h: int): TimeInterval {.inline.} =
  ## TimeInterval of `h` hours.
  ##
  ## `echo getTime() + 2.hours`
  initTimeInterval(hours = h)

proc days*(d: int): TimeInterval {.inline.} =
  ## TimeInterval of `d` days.
  ##
  ## `echo getTime() + 2.days`
  initTimeInterval(days = d)

proc weeks*(w: int): TimeInterval {.inline.} =
  ## TimeInterval of `w` weeks.
  ##
  ## `echo getTime() + 2.weeks`
  initTimeInterval(weeks = w)

proc months*(m: int): TimeInterval {.inline.} =
  ## TimeInterval of `m` months.
  ##
  ## `echo getTime() + 2.months`
  initTimeInterval(months = m)

proc years*(y: int): TimeInterval {.inline.} =
  ## TimeInterval of `y` years.
  ##
  ## `echo getTime() + 2.years`
  initTimeInterval(years = y)

proc evaluateInterval(dt: DateTime, interval: TimeInterval):
    tuple[adjDur, absDur: Duration] =
  ## Evaluates how many nanoseconds the interval is worth
  ## in the context of `dt`.
  ## The result in split into an adjusted diff and an absolute diff.
  var months = interval.years * 12 + interval.months
  var curYear = dt.year
  var curMonth = dt.month
  result = default(tuple[adjDur, absDur: Duration])
  # Subtracting
  if months < 0:
    for mth in countdown(-1 * months, 1):
      if curMonth == mJan:
        curMonth = mDec
        curYear.dec
      else:
        curMonth.dec()
      let days = getDaysInMonth(curMonth, curYear)
      result.adjDur = result.adjDur - initDuration(days = days)
  # Adding
  else:
    for mth in 1 .. months:
      let days = getDaysInMonth(curMonth, curYear)
      result.adjDur = result.adjDur + initDuration(days = days)
      if curMonth == mDec:
        curMonth = mJan
        curYear.inc
      else:
        curMonth.inc()

  result.adjDur = result.adjDur + initDuration(
    days = interval.days,
    weeks = interval.weeks)
  result.absDur = initDuration(
    nanoseconds = interval.nanoseconds,
    microseconds = interval.microseconds,
    milliseconds = interval.milliseconds,
    seconds = interval.seconds,
    minutes = interval.minutes,
    hours = interval.hours)

proc `+`*(dt: DateTime, interval: TimeInterval): DateTime =
  ## Adds `interval` to `dt`. Components from `interval` are added
  ## in the order of their size, i.e. first the `years` component, then the
  ## `months` component and so on. The returned `DateTime` will have the
  ## same timezone as the input.
  ##
  ## Note that when adding months, monthday overflow is allowed. This means that
  ## if the resulting month doesn't have enough days it, the month will be
  ## incremented and the monthday will be set to the number of days overflowed.
  ## So adding one month to `31 October` will result in `31 November`, which
  ## will overflow and result in `1 December`.
  runnableExamples:
    let dt = dateTime(2017, mMar, 30, 00, 00, 00, 00, utc())
    doAssert $(dt + 1.months) == "2017-04-30T00:00:00Z"
    # This is correct and happens due to monthday overflow.
    doAssert $(dt - 1.months) == "2017-03-02T00:00:00Z"
  let (adjDur, absDur) = evaluateInterval(dt, interval)

  if adjDur != DurationZero:
    var zt = dt.timezone.zonedTimeFromAdjTime(dt.toAdjTime + adjDur)
    if absDur != DurationZero:
      zt = dt.timezone.zonedTimeFromTime(zt.time + absDur)
      result = initDateTime(zt, dt.timezone)
    else:
      result = initDateTime(zt, dt.timezone)
  else:
    var zt = dt.timezone.zonedTimeFromTime(dt.toTime + absDur)
    result = initDateTime(zt, dt.timezone)

proc `-`*(dt: DateTime, interval: TimeInterval): DateTime =
  ## Subtract `interval` from `dt`. Components from `interval` are
  ## subtracted in the order of their size, i.e. first the `years` component,
  ## then the `months` component and so on. The returned `DateTime` will
  ## have the same timezone as the input.
  runnableExamples:
    let dt = dateTime(2017, mMar, 30, 00, 00, 00, 00, utc())
    doAssert $(dt - 5.days) == "2017-03-25T00:00:00Z"

  dt + (-interval)

proc `+`*(time: Time, interval: TimeInterval): Time =
  ## Adds `interval` to `time`.
  ## If `interval` contains any years, months, weeks or days the operation
  ## is performed in the local timezone.
  runnableExamples:
    let tm = fromUnix(0)
    doAssert tm + 5.seconds == fromUnix(5)

  if interval.isStaticInterval:
    time + evaluateStaticInterval(interval)
  else:
    toTime(time.local + interval)

proc `-`*(time: Time, interval: TimeInterval): Time =
  ## Subtracts `interval` from Time `time`.
  ## If `interval` contains any years, months, weeks or days the operation
  ## is performed in the local timezone.
  runnableExamples:
    let tm = fromUnix(5)
    doAssert tm - 5.seconds == fromUnix(0)

  if interval.isStaticInterval:
    time - evaluateStaticInterval(interval)
  else:
    toTime(time.local - interval)

proc `+=`*(a: var DateTime, b: TimeInterval) =
  a = a + b

proc `-=`*(a: var DateTime, b: TimeInterval) =
  a = a - b

proc `+=`*(t: var Time, b: TimeInterval) =
  t = t + b

proc `-=`*(t: var Time, b: TimeInterval) =
  t = t - b

#
# Iso week
#

proc initDateTime*(weekday: WeekDay, isoweek: IsoWeekRange, isoyear: IsoYear,
                   hour: HourRange, minute: MinuteRange, second: SecondRange,
                   nanosecond: NanosecondRange,
                   zone: Timezone = local()): DateTime {.raises: [], tags: [], since: (1, 5).} =
  ## Create a new `DateTime <#DateTime>`_ from a weekday and an ISO 8601 week number and year
  ## in the specified timezone.
  ##
  ## .. warning:: The ISO week-based year can correspond to the following or previous year from 29 December to January 3.
  runnableExamples:
    assert initDateTime(21, mApr, 2018, 00, 00, 00) == initDateTime(dSat, 16, 2018.IsoYear, 00, 00, 00)
    assert initDateTime(30, mDec, 2019, 00, 00, 00) == initDateTime(dMon, 01, 2020.IsoYear, 00, 00, 00)
    assert initDateTime(13, mSep, 2020, 00, 00, 00) == initDateTime(dSun, 37, 2020.IsoYear, 00, 00, 00)
    assert initDateTime(2, mJan, 2021, 00, 00, 00) == initDateTime(dSat, 53, 2020.IsoYear, 00, 00, 00)

  # source https://webspace.science.uu.nl/~gent0113/calendar/isocalendar.htm
  let d = isoweek * 7 + weekday.int - initDateTime(4, mJan, isoyear.int, 00, 00, 00, zone).weekday.int - 4
  initDateTime(1, mJan, isoyear.int, hour, minute, second, nanosecond, zone) + initTimeInterval(days=d)

proc initDateTime*(weekday: WeekDay, isoweek: IsoWeekRange, isoyear: IsoYear,
                   hour: HourRange, minute: MinuteRange, second: SecondRange,
                   zone: Timezone = local()): DateTime {.raises: [], tags: [], since: (1, 5).} =
  initDateTime(weekday, isoweek, isoyear, hour, minute, second, 0, zone)

#
# Other
#

proc epochTime*(): float {.tags: [TimeEffect].} =
  ## Gets time after the UNIX epoch (1970) in seconds. It is a float
  ## because sub-second resolution is likely to be supported (depending
  ## on the hardware/OS).
  ##
  ## `getTime` should generally be preferred over this proc.
  ##
  ## .. warning:: Unsuitable for benchmarking (but still better than `now`),
  ##    use `monotimes.getMonoTime` or `cpuTime` instead, depending on the use case.
  when defined(js):
    result = newDate().getTime() / 1000
  elif defined(macosx):
    var a {.noinit.}: Timeval
    gettimeofday(a)
    result = toBiggestFloat(a.tv_sec.int64) + toBiggestFloat(
        a.tv_usec)*0.00_0001
  elif defined(posix):
    var ts {.noinit.}: Timespec
    discard clock_gettime(CLOCK_REALTIME, ts)
    result = toBiggestFloat(ts.tv_sec.int64) +
      toBiggestFloat(ts.tv_nsec.int64) / 1_000_000_000
  elif defined(windows):
    var f {.noinit.}: winlean.FILETIME
    getSystemTimeAsFileTime(f)
    var i64 = rdFileTime(f) - epochDiff
    var secs = i64 div rateDiff
    var subsecs = i64 mod rateDiff
    result = toFloat(int(secs)) + toFloat(int(subsecs)) * 0.0000001
  else:
    {.error: "unknown OS".}

when not defined(js):
  type
    Clock {.importc: "clock_t".} = distinct int

  proc getClock(): Clock
      {.importc: "clock", header: "<time.h>", tags: [TimeEffect], used, sideEffect.}

  var
    clocksPerSec {.importc: "CLOCKS_PER_SEC", nodecl, used.}: int

  proc cpuTime*(): float {.tags: [TimeEffect].} =
    ## Gets time spent that the CPU spent to run the current process in
    ## seconds. This may be more useful for benchmarking than `epochTime`.
    ## However, it may measure the real time instead (depending on the OS).
    ## The value of the result has no meaning.
    ## To generate useful timing values, take the difference between
    ## the results of two `cpuTime` calls:
    runnableExamples:
      var t0 = cpuTime()
      # some useless work here (calculate fibonacci)
      var fib = @[0, 1, 1]
      for i in 1..10:
        fib.add(fib[^1] + fib[^2])
      echo "CPU time [s] ", cpuTime() - t0
      echo "Fib is [s] ", fib
    ## When the flag `--benchmarkVM` is passed to the compiler, this proc is
    ## also available at compile time
    when defined(posix) and not defined(osx) and declared(CLOCK_THREAD_CPUTIME_ID):
      # 'clocksPerSec' is a compile-time constant, possibly a
      # rather awful one, so use clock_gettime instead
      var ts: Timespec
      discard clock_gettime(CLOCK_THREAD_CPUTIME_ID, ts)
      result = toFloat(ts.tv_sec.int) +
        toFloat(ts.tv_nsec.int) / 1_000_000_000
    else:
      result = toFloat(int(getClock())) / toFloat(clocksPerSec)


#
# Deprecations
#

proc `nanosecond=`*(dt: var DateTime, value: NanosecondRange) {.deprecated: "Deprecated since v1.3.1".} =
  dt.nanosecond = value

proc `second=`*(dt: var DateTime, value: SecondRange) {.deprecated: "Deprecated since v1.3.1".} =
  dt.second = value

proc `minute=`*(dt: var DateTime, value: MinuteRange) {.deprecated: "Deprecated since v1.3.1".} =
  dt.minute = value

proc `hour=`*(dt: var DateTime, value: HourRange) {.deprecated: "Deprecated since v1.3.1".} =
  dt.hour = value

proc `monthdayZero=`*(dt: var DateTime, value: int) {.deprecated: "Deprecated since v1.3.1".} =
  dt.monthdayZero = value

proc `monthZero=`*(dt: var DateTime, value: int) {.deprecated: "Deprecated since v1.3.1".} =
  dt.monthZero = value

proc `year=`*(dt: var DateTime, value: int) {.deprecated: "Deprecated since v1.3.1".} =
  dt.year = value

proc `weekday=`*(dt: var DateTime, value: WeekDay) {.deprecated: "Deprecated since v1.3.1".} =
  dt.weekday = value

proc `yearday=`*(dt: var DateTime, value: YeardayRange) {.deprecated: "Deprecated since v1.3.1".} =
  dt.yearday = value

proc `isDst=`*(dt: var DateTime, value: bool) {.deprecated: "Deprecated since v1.3.1".} =
  dt.isDst = value

proc `timezone=`*(dt: var DateTime, value: Timezone) {.deprecated: "Deprecated since v1.3.1".} =
  dt.timezone = value

proc `utcOffset=`*(dt: var DateTime, value: int) {.deprecated: "Deprecated since v1.3.1".} =
  dt.utcOffset = value
