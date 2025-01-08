discard """
  matrix: "--mm:refc; --mm:orc; --backend:js --jsbigint64:on; --backend:js --jsbigint64:off -d:nimStringHash2"
"""

import times, strutils, unittest
import std/assertions

when not defined(js):
  import os

proc staticTz(hours, minutes, seconds: int = 0): Timezone {.noSideEffect.} =
  let offset = hours * 3600 + minutes * 60 + seconds

  proc zonedTimeFromAdjTime(adjTime: Time): ZonedTime =
    result = default(ZonedTime)
    result.isDst = false
    result.utcOffset = offset
    result.time = adjTime + initDuration(seconds = offset)

  proc zonedTimeFromTime(time: Time): ZonedTime =
    result = default(ZonedTime)
    result.isDst = false
    result.utcOffset = offset
    result.time = time

  newTimezone("", zonedTimeFromTime, zonedTimeFromAdjTime)

template parseTest(s, f, sExpected: string, ydExpected: int) =
  let
    parsed = s.parse(f, utc())
    parsedStr = $parsed
  check parsedStr == sExpected
  check parsed.yearday == ydExpected

template parseTestExcp(s, f: string) =
  expect ValueError:
    let parsed = s.parse(f)

template parseTestTimeOnly(s, f, sExpected: string) =
  check sExpected in $s.parse(f, utc())

# because setting a specific timezone for testing is platform-specific, we use
# explicit timezone offsets in all tests.
template runTimezoneTests() =
  parseTest("Tuesday at 09:04am on Dec 15, 2015 +0",
      "dddd 'at' hh:mmtt 'on' MMM d, yyyy z", "2015-12-15T09:04:00Z", 348)
  # ANSIC       = "Mon Jan _2 15:04:05 2006"
  parseTest("Thu Jan 12 15:04:05 2006 +0", "ddd MMM dd HH:mm:ss yyyy z",
      "2006-01-12T15:04:05Z", 11)
  # UnixDate    = "Mon Jan _2 15:04:05 MST 2006"
  parseTest("Thu Jan 12 15:04:05 2006 +0", "ddd MMM dd HH:mm:ss yyyy z",
      "2006-01-12T15:04:05Z", 11)
  # RubyDate    = "Mon Jan 02 15:04:05 -0700 2006"
  parseTest("Mon Feb 29 15:04:05 -07:00 2016 +0", "ddd MMM dd HH:mm:ss zzz yyyy z",
      "2016-02-29T15:04:05Z", 59) # leap day
  # RFC822      = "02 Jan 06 15:04 MST"
  parseTest("12 Jan 16 15:04 +0", "dd MMM yy HH:mm z",
      "2016-01-12T15:04:00Z", 11)
  # RFC822Z     = "02 Jan 06 15:04 -0700" # RFC822 with numeric zone
  parseTest("01 Mar 16 15:04 -07:00", "dd MMM yy HH:mm zzz",
      "2016-03-01T22:04:00Z", 60) # day after february in leap year
  # RFC850      = "Monday, 02-Jan-06 15:04:05 MST"
  parseTest("Monday, 12-Jan-06 15:04:05 +0", "dddd, dd-MMM-yy HH:mm:ss z",
      "2006-01-12T15:04:05Z", 11)
  # RFC1123     = "Mon, 02 Jan 2006 15:04:05 MST"
  parseTest("Sun, 01 Mar 2015 15:04:05 +0", "ddd, dd MMM yyyy HH:mm:ss z",
      "2015-03-01T15:04:05Z", 59) # day after february in non-leap year
  # RFC1123Z    = "Mon, 02 Jan 2006 15:04:05 -0700" # RFC1123 with numeric zone
  parseTest("Thu, 12 Jan 2006 15:04:05 -07:00", "ddd, dd MMM yyyy HH:mm:ss zzz",
      "2006-01-12T22:04:05Z", 11)
  # RFC3339     = "2006-01-02T15:04:05Z07:00"
  parseTest("2006-01-12T15:04:05Z-07:00", "yyyy-MM-dd'T'HH:mm:ss'Z'zzz",
      "2006-01-12T22:04:05Z", 11)
  # RFC3339Nano = "2006-01-02T15:04:05.999999999Z07:00"
  parseTest("2006-01-12T15:04:05.999999999Z-07:00",
      "yyyy-MM-dd'T'HH:mm:ss.'999999999Z'zzz", "2006-01-12T22:04:05Z", 11)
  for tzFormat in ["z", "zz", "zzz"]:
    # formatting timezone as 'Z' for UTC
    parseTest("2001-01-12T22:04:05Z", "yyyy-MM-dd'T'HH:mm:ss" & tzFormat,
        "2001-01-12T22:04:05Z", 11)
  # timezone offset formats
  parseTest("2001-01-12T15:04:05 +7", "yyyy-MM-dd'T'HH:mm:ss z",
      "2001-01-12T08:04:05Z", 11)
  parseTest("2001-01-12T15:04:05 +07", "yyyy-MM-dd'T'HH:mm:ss zz",
      "2001-01-12T08:04:05Z", 11)
  parseTest("2001-01-12T15:04:05 +07:00", "yyyy-MM-dd'T'HH:mm:ss zzz",
      "2001-01-12T08:04:05Z", 11)
  parseTest("2001-01-12T15:04:05 +07:30:59", "yyyy-MM-dd'T'HH:mm:ss zzzz",
      "2001-01-12T07:33:06Z", 11)
  parseTest("2001-01-12T15:04:05 +0700", "yyyy-MM-dd'T'HH:mm:ss ZZZ",
      "2001-01-12T08:04:05Z", 11)
  parseTest("2001-01-12T15:04:05 +073059", "yyyy-MM-dd'T'HH:mm:ss ZZZZ",
      "2001-01-12T07:33:06Z", 11)
  # Kitchen     = "3:04PM"
  parseTestTimeOnly("3:04PM", "h:mmtt", "15:04:00")

  # Bug with parse not setting DST properly if the current local DST differs from
  # the date being parsed. Need to test parse dates both in and out of DST. We
  # are testing that be relying on the fact that transforming a TimeInfo to a Time
  # and back again will correctly set the DST value. With the incorrect parse
  # behavior this will introduce a one hour offset from the named time and the
  # parsed time if the DST value differs between the current time and the date we
  # are parsing.
  let dstT1 = parse("2016-01-01 00:00:00", "yyyy-MM-dd HH:mm:ss")
  let dstT2 = parse("2016-06-01 00:00:00", "yyyy-MM-dd HH:mm:ss")
  check dstT1 == toTime(dstT1).local
  check dstT2 == toTime(dstT2).local

  block dstTest:
    # parsing will set isDST in relation to the local time. We take a date in
    # January and one in July to maximize the probability to hit one date with DST
    # and one without on the local machine. However, this is not guaranteed.
    let
      parsedJan = parse("2016-01-05 04:00:00+01:00", "yyyy-MM-dd HH:mm:sszzz")
      parsedJul = parse("2016-07-01 04:00:00+01:00", "yyyy-MM-dd HH:mm:sszzz")
    check toTime(parsedJan).toUnix == 1451962800
    check toTime(parsedJul).toUnix == 1467342000

template usingTimezone(tz: string, body: untyped) =
  when defined(linux) or defined(macosx):
    let oldZone = getEnv("TZ")
    putEnv("TZ", tz)
    body
    putEnv("TZ", oldZone)

block: # ttimes

  # Generate tests for multiple timezone files where available
  # Set the TZ env var for each test
  when defined(linux) or defined(macosx):
    let tz_dir = getEnv("TZDIR", "/usr/share/zoneinfo")
    const f = "yyyy-MM-dd HH:mm zzz"

    var tz_cnt = 0
    for timezone in walkFiles(tz_dir & "/**/*"):
      if symlinkExists(timezone) or timezone.endsWith(".tab") or
          timezone.endsWith(".list"):
        continue

      usingTimezone(timezone):
        test "test for " & timezone:
          tz_cnt.inc
          runTimezoneTests()

    test "enough timezone files tested":
      check tz_cnt > 10

  else:
    # not on Linux or macosx: run in the local timezone only
    test "parseTest":
      runTimezoneTests()

  block: # dst handling
    usingTimezone("Europe/Stockholm"):
      # In case of an impossible time, the time is moved to after the
      # impossible time period
      check initDateTime(26, mMar, 2017, 02, 30, 00).format(f) ==
        "2017-03-26 03:30 +02:00"
      # In case of an ambiguous time, the earlier time is chosen
      check initDateTime(29, mOct, 2017, 02, 00, 00).format(f) ==
        "2017-10-29 02:00 +02:00"
      # These are just dates on either side of the dst switch
      check initDateTime(29, mOct, 2017, 01, 00, 00).format(f) ==
        "2017-10-29 01:00 +02:00"
      check initDateTime(29, mOct, 2017, 01, 00, 00).isDst
      check initDateTime(29, mOct, 2017, 03, 01, 00).format(f) ==
        "2017-10-29 03:01 +01:00"
      check (not initDateTime(29, mOct, 2017, 03, 01, 00).isDst)

      check initDateTime(21, mOct, 2017, 01, 00, 00).format(f) ==
        "2017-10-21 01:00 +02:00"

  block: # issue #6520
    usingTimezone("Europe/Stockholm"):
      var local = fromUnix(1469275200).local
      var utc = fromUnix(1469275200).utc

      let claimedOffset = initDuration(seconds = local.utcOffset)
      local.utcOffset = 0
      check claimedOffset == utc.toTime - local.toTime

  block: # issue #5704
    usingTimezone("Asia/Seoul"):
      let diff = parse("19700101-000000", "yyyyMMdd-hhmmss").toTime -
        parse("19000101-000000", "yyyyMMdd-hhmmss").toTime
      check diff == initDuration(seconds = 2208986872)

  block: # issue #6465
    usingTimezone("Europe/Stockholm"):
      let dt = parse("2017-03-25 12:00", "yyyy-MM-dd hh:mm")
      check $(dt + initTimeInterval(days = 1)) == "2017-03-26T12:00:00+02:00"
      check $(dt + initDuration(days = 1)) == "2017-03-26T13:00:00+02:00"

  block: # adding/subtracting time across dst
    usingTimezone("Europe/Stockholm"):
      let dt1 = initDateTime(26, mMar, 2017, 03, 00, 00)
      check $(dt1 - 1.seconds) == "2017-03-26T01:59:59+01:00"

      var dt2 = initDateTime(29, mOct, 2017, 02, 59, 59)
      check  $(dt2 + 1.seconds) == "2017-10-29T02:00:00+01:00"

  block: # datetime before epoch
    check $fromUnix(-2147483648).utc == "1901-12-13T20:45:52Z"

  block: # incorrect inputs: empty string
    parseTestExcp("", "yyyy-MM-dd")

  block: # incorrect inputs: year
    parseTestExcp("20-02-19", "yyyy-MM-dd")

  block: # incorrect inputs: month number
    parseTestExcp("2018-2-19", "yyyy-MM-dd")

  block: # incorrect inputs: month name
    parseTestExcp("2018-Fe", "yyyy-MMM-dd")

  block: # incorrect inputs: day
    parseTestExcp("2018-02-1", "yyyy-MM-dd")

  block: # incorrect inputs: day of week
    parseTestExcp("2018-Feb-Mo", "yyyy-MMM-ddd")

  block: # incorrect inputs: hour
    parseTestExcp("2018-02-19 1:30", "yyyy-MM-dd hh:mm")

  block: # incorrect inputs: minute
    parseTestExcp("2018-02-19 16:3", "yyyy-MM-dd hh:mm")

  block: # incorrect inputs: second
    parseTestExcp("2018-02-19 16:30:0", "yyyy-MM-dd hh:mm:ss")

  block: # incorrect inputs: timezone (z)
    parseTestExcp("2018-02-19 16:30:00 ", "yyyy-MM-dd hh:mm:ss z")

  block: # incorrect inputs: timezone (zz) 1
    parseTestExcp("2018-02-19 16:30:00 ", "yyyy-MM-dd hh:mm:ss zz")

  block: # incorrect inputs: timezone (zz) 2
    parseTestExcp("2018-02-19 16:30:00 +1", "yyyy-MM-dd hh:mm:ss zz")

  block: # incorrect inputs: timezone (zzz) 1
    parseTestExcp("2018-02-19 16:30:00 ", "yyyy-MM-dd hh:mm:ss zzz")

  block: # incorrect inputs: timezone (zzz) 2
    parseTestExcp("2018-02-19 16:30:00 +01:", "yyyy-MM-dd hh:mm:ss zzz")

  block: # incorrect inputs: timezone (zzz) 3
    parseTestExcp("2018-02-19 16:30:00 +01:0", "yyyy-MM-dd hh:mm:ss zzz")

  block: # incorrect inputs: year (yyyy/uuuu)
    parseTestExcp("-0001", "yyyy")
    parseTestExcp("-0001", "YYYY")
    parseTestExcp("1", "yyyy")
    parseTestExcp("12345", "yyyy")
    parseTestExcp("1", "uuuu")
    parseTestExcp("12345", "uuuu")
    parseTestExcp("-1 BC", "UUUU g")

  block: # incorrect inputs: invalid sign
    parseTestExcp("+1", "YYYY")
    parseTestExcp("+1", "dd")
    parseTestExcp("+1", "MM")
    parseTestExcp("+1", "hh")
    parseTestExcp("+1", "mm")
    parseTestExcp("+1", "ss")

  block: # _ as a separator
    discard parse("2000_01_01", "YYYY'_'MM'_'dd")

  block: # dynamic timezone
    let tz = staticTz(seconds = -9000)
    let dt = initDateTime(1, mJan, 2000, 12, 00, 00, tz)
    check dt.utcOffset == -9000
    check dt.isDst == false
    check $dt == "2000-01-01T12:00:00+02:30"
    check $dt.utc == "2000-01-01T09:30:00Z"
    check $dt.utc.inZone(tz) == $dt

  block: # isLeapYear
    check isLeapYear(2016)
    check (not isLeapYear(2015))
    check isLeapYear(2000)
    check (not isLeapYear(1900))

  block: # TimeInterval
    let t = fromUnix(876124714).utc # Mon 6 Oct 08:58:34 BST 1997
    # Interval tests
    let t2 = t - 2.years
    check t2.year == 1995
    let t3 = (t - 7.years - 34.minutes - 24.seconds)
    check t3.year == 1990
    check t3.minute == 24
    check t3.second == 10
    check (t + 1.hours).toTime.toUnix == t.toTime.toUnix + 60 * 60
    check (t - 1.hours).toTime.toUnix == t.toTime.toUnix - 60 * 60

  block: # TimeInterval - months
    var dt = initDateTime(1, mFeb, 2017, 00, 00, 00, utc())
    check $(dt - initTimeInterval(months = 1)) == "2017-01-01T00:00:00Z"
    dt = initDateTime(15, mMar, 2017, 00, 00, 00, utc())
    check $(dt - initTimeInterval(months = 1)) == "2017-02-15T00:00:00Z"
    dt = initDateTime(31, mMar, 2017, 00, 00, 00, utc())
    # This happens due to monthday overflow. It's consistent with Phobos.
    check $(dt - initTimeInterval(months = 1)) == "2017-03-03T00:00:00Z"

  block: # duration
    let d = initDuration
    check d(hours = 48) + d(days = 5) == d(weeks = 1)
    let dt = initDateTime(01, mFeb, 2000, 00, 00, 00, 0, utc()) + d(milliseconds = 1)
    check dt.nanosecond == convert(Milliseconds, Nanoseconds, 1)
    check d(seconds = 1, milliseconds = 500) * 2 == d(seconds = 3)
    check d(seconds = 3) div 2 == d(seconds = 1, milliseconds = 500)
    check d(milliseconds = 1001).inSeconds == 1
    check d(seconds = 1, milliseconds = 500) - d(milliseconds = 1250) ==
      d(milliseconds = 250)
    check d(seconds = 1, milliseconds = 1) < d(seconds = 1, milliseconds = 2)
    check d(seconds = 1) <= d(seconds = 1)
    check d(seconds = 0) - d(milliseconds = 1500) == d(milliseconds = -1500)
    check d(milliseconds = -1500) == d(seconds = -1, milliseconds = -500)
    check d(seconds = -1, milliseconds = 500) == d(milliseconds = -500)
    check initDuration(seconds = 1, nanoseconds = 2) <=
      initDuration(seconds = 1, nanoseconds = 3)
    check (initDuration(seconds = 1, nanoseconds = 3) <=
      initDuration(seconds = 1, nanoseconds = 1)).not

  block: # large/small dates
    discard initDateTime(1, mJan, -35_000, 12, 00, 00, utc())
    # with local tz
    discard initDateTime(1, mJan, -35_000, 12, 00, 00)
    discard initDateTime(1, mJan,  35_000, 12, 00, 00)
    # with duration/timeinterval
    let dt = initDateTime(1, mJan, -35_000, 12, 00, 00, utc()) +
      initDuration(seconds = 1)
    check dt.second == 1
    let dt2 = dt + 35_001.years
    check $dt2 == "0001-01-01T12:00:01Z"

  block: # compare datetimes
    var dt1 = now()
    var dt2 = dt1
    check dt1 == dt2
    check dt1 <= dt2
    dt2 = dt2 + 1.seconds
    check dt1 < dt2

  block: # adding/subtracting TimeInterval
    # add/subtract TimeIntervals and Time/TimeInfo
    let now = getTime().utc
    let isSpecial = now.isLeapDay
    check now + convert(Seconds, Nanoseconds, 1).nanoseconds == now + 1.seconds
    check now + 1.weeks == now + 7.days
    check now - 1.seconds == now - 3.seconds + 2.seconds
    check now + 65.seconds == now + 1.minutes + 5.seconds
    check now + 60.minutes == now + 1.hours
    check now + 24.hours == now + 1.days
    if not isSpecial:
      check now + 13.months == now + 1.years + 1.months
    check toUnix(fromUnix(0) + 2.seconds) == 2
    check toUnix(fromUnix(0) - 2.seconds) == -2
    var ti1 = now + 1.years
    ti1 = ti1 - 1.years
    if not isSpecial:
      check ti1 == now
    ti1 = ti1 + 1.days
    if not isSpecial:
      check ti1 == now + 1.days

    # Bug with adding a day to a Time
    let day = 24.hours
    let tomorrow = now + day
    check tomorrow - now == initDuration(days = 1)

  # Disabled for JS because it fails due to precision errors
  # (The JS target uses float64 for int64).
  when not defined(js):
    test "fromWinTime/toWinTime":
      check 0.fromUnix.toWinTime.fromWinTime.toUnix == 0
      check (-1).fromWinTime.nanosecond == convert(Seconds, Nanoseconds, 1) - 100
      check (-1).fromWinTime.toWinTime == -1
      # One nanosecond is discarded due to differences in time resolution
      check initTime(0, 101).toWinTime.fromWinTime.nanosecond == 100
      check initTime(0, 101).toWinTime.fromWinTime.nanosecond == 100

  block: # issue 7620
    let layout = "M/d/yyyy' 'h:mm:ss' 'tt' 'z"
    let t7620_am = parse("4/15/2017 12:01:02 AM +0", layout, utc())
    check t7620_am.format(layout) == "4/15/2017 12:01:02 AM Z"
    let t7620_pm = parse("4/15/2017 12:01:02 PM +0", layout, utc())
    check t7620_pm.format(layout) == "4/15/2017 12:01:02 PM Z"

  block: # format
    var dt = initDateTime(1, mJan, -0001,
                          17, 01, 02, 123_456_789,
                          staticTz(hours = 1, minutes = 2, seconds = 3))
    check dt.format("d") == "1"
    check dt.format("dd") == "01"
    check dt.format("ddd") == "Fri"
    check dt.format("dddd") == "Friday"
    check dt.format("h") == "5"
    check dt.format("hh") == "05"
    check dt.format("H") == "17"
    check dt.format("HH") == "17"
    check dt.format("m") == "1"
    check dt.format("mm") == "01"
    check dt.format("M") == "1"
    check dt.format("MM") == "01"
    check dt.format("MMM") == "Jan"
    check dt.format("MMMM") == "January"
    check dt.format("s") == "2"
    check dt.format("ss") == "02"
    check dt.format("t") == "P"
    check dt.format("tt") == "PM"
    check dt.format("yy") == "02"
    check dt.format("yyyy") == "0002"
    check dt.format("YYYY") == "2"
    check dt.format("uuuu") == "-0001"
    check dt.format("UUUU") == "-1"
    check dt.format("z") == "-1"
    check dt.format("zz") == "-01"
    check dt.format("zzz") == "-01:02"
    check dt.format("zzzz") == "-01:02:03"
    check dt.format("g") == "BC"

    check dt.format("fff") == "123"
    check dt.format("ffffff") == "123456"
    check dt.format("fffffffff") == "123456789"
    dt.nanosecond = 1
    check dt.format("fff") == "000"
    check dt.format("ffffff") == "000000"
    check dt.format("fffffffff") == "000000001"

    dt.year = 12345
    check dt.format("yyyy") == "+12345"
    check dt.format("uuuu") == "+12345"
    dt.year = -12345
    check dt.format("yyyy") == "+12346"
    check dt.format("uuuu") == "-12345"

    expect ValueError:
      discard initTimeFormat("'")

    expect ValueError:
      discard initTimeFormat("'foo")

    expect ValueError:
      discard initTimeFormat("foo'")

    for tz in [
        (staticTz(seconds = 0), "+0", "+00", "+00:00"), # UTC
        (staticTz(seconds = -3600), "+1", "+01", "+01:00"), # CET
        (staticTz(seconds = -39600), "+11", "+11", "+11:00"), # two digits
        (staticTz(seconds = -1800), "+0", "+00", "+00:30"), # half an hour
        (staticTz(seconds = 7200), "-2", "-02", "-02:00"), # positive
        (staticTz(seconds = 38700), "-10", "-10", "-10:45")]: # positive with three quaters hour
      let dt = initDateTime(1, mJan, 2000, 00, 00, 00, tz[0])
      doAssert dt.format("z") == tz[1]
      doAssert dt.format("zz") == tz[2]
      doAssert dt.format("zzz") == tz[3]

  block: # format locale
    let loc = DateTimeLocale(
      MMM: ["Fir","Sec","Thi","Fou","Fif","Six","Sev","Eig","Nin","Ten","Ele","Twe"],
      MMMM: ["Firsty", "Secondy", "Thirdy", "Fourthy", "Fifthy", "Sixthy", "Seventhy", "Eighthy", "Ninthy", "Tenthy", "Eleventhy", "Twelfthy"],
      ddd: ["Red", "Ora.", "Yel.", "Gre.", "Blu.", "Vio.", "Whi."],
      dddd: ["Red", "Orange", "Yellow", "Green", "Blue", "Violet", "White"],
    )
    var dt = initDateTime(5, mJan, 2010, 17, 01, 02, utc())
    check dt.format("d", loc) == "5"
    check dt.format("dd", loc) == "05"
    check dt.format("ddd", loc) == "Ora."
    check dt.format("dddd", loc) == "Orange"
    check dt.format("M", loc) == "1"
    check dt.format("MM", loc) == "01"
    check dt.format("MMM", loc) == "Fir"
    check dt.format("MMMM", loc) == "Firsty"

  block: # parse
    check $parse("20180101", "yyyyMMdd", utc()) == "2018-01-01T00:00:00Z"
    parseTestExcp("+120180101", "yyyyMMdd")

    check parse("1", "YYYY", utc()).year == 1
    check parse("1 BC", "YYYY g", utc()).year == 0
    check parse("0001 BC", "yyyy g", utc()).year == 0
    check parse("+12345 BC", "yyyy g", utc()).year == -12344
    check parse("1 AD", "YYYY g", utc()).year == 1
    check parse("0001 AD", "yyyy g", utc()).year == 1
    check parse("+12345 AD", "yyyy g", utc()).year == 12345

    check parse("-1", "UUUU", utc()).year == -1
    check parse("-0001", "uuuu", utc()).year == -1

    discard parse("foobar", "'foobar'")
    discard parse("foo'bar", "'foo''''bar'")
    discard parse("'", "''")

    parseTestExcp("2000 A", "yyyy g")

  block: # parse locale
    let loc = DateTimeLocale(
      MMM: ["Fir","Sec","Thi","Fou","Fif","Six","Sev","Eig","Nin","Ten","Ele","Twe"],
      MMMM: ["Firsty", "Secondy", "Thirdy", "Fourthy", "Fifthy", "Sixthy", "Seventhy", "Eighthy", "Ninthy", "Tenthy", "Eleventhy", "Twelfthy"],
      ddd: ["Red", "Ora.", "Yel.", "Gre.", "Blu.", "Vio.", "Whi."],
      dddd: ["Red", "Orange", "Yellow", "Green", "Blue", "Violet", "White"],
    )
    check $parse("02 Fir 2019", "dd MMM yyyy", utc(), loc) == "2019-01-02T00:00:00Z"
    check $parse("Fourthy 6, 2017", "MMMM d, yyyy", utc(), loc) == "2017-04-06T00:00:00Z"

  block: # timezoneConversion
    var l = now()
    let u = l.utc
    l = u.local

    check l.timezone == local()
    check u.timezone == utc()

  block: # getDayOfWeek
    check getDayOfWeek(01, mJan, 0000) == dSat
    check getDayOfWeek(01, mJan, -0023) == dSat
    check getDayOfWeek(21, mSep, 1900) == dFri
    check getDayOfWeek(01, mJan, 1970) == dThu
    check getDayOfWeek(21, mSep, 1970) == dMon
    check getDayOfWeek(01, mJan, 2000) == dSat
    check getDayOfWeek(01, mJan, 2021) == dFri

  block: # between - simple
    let x = initDateTime(10, mJan, 2018, 13, 00, 00)
    let y = initDateTime(11, mJan, 2018, 12, 00, 00)
    doAssert x + between(x, y) == y

  block: # between - dst start
    usingTimezone("Europe/Stockholm"):
      let x = initDateTime(25, mMar, 2018, 00, 00, 00)
      let y = initDateTime(25, mMar, 2018, 04, 00, 00)
      doAssert x + between(x, y) == y

  block: # between - empty interval
    let x = now()
    let y = x
    doAssert x + between(x, y) == y

  block: # between - dst end
    usingTimezone("Europe/Stockholm"):
      let x = initDateTime(27, mOct, 2018, 02, 00, 00)
      let y = initDateTime(28, mOct, 2018, 01, 00, 00)
      doAssert x + between(x, y) == y

  block: # between - long day
    usingTimezone("Europe/Stockholm"):
      # This day is 25 hours long in Europe/Stockholm
      let x = initDateTime(28, mOct, 2018, 00, 30, 00)
      let y = initDateTime(29, mOct, 2018, 00, 00, 00)
      doAssert between(x, y) == 24.hours + 30.minutes
      doAssert x + between(x, y) == y

  block: # between - offset change edge case
    # This test case is important because in this case
    # `x + between(x.utc, y.utc) == y` is not true, which is very rare.
    usingTimezone("America/Belem"):
      let x = initDateTime(24, mOct, 1987, 00, 00, 00)
      let y = initDateTime(26, mOct, 1987, 23, 00, 00)
      doAssert x + between(x, y) == y
      doAssert y + between(y, x) == x

  block: # between - all units
    let x = initDateTime(1, mJan, 2000, 00, 00, 00, utc())
    let ti = initTimeInterval(1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
    let y = x + ti
    doAssert between(x, y) == ti
    doAssert between(y, x) == -ti

  block: # between - monthday overflow
      let x = initDateTime(31, mJan, 2001, 00, 00, 00, utc())
      let y = initDateTime(1, mMar, 2001, 00, 00, 00, utc())
      doAssert x + between(x, y) == y

  block: # between - misc
    block:
      let x = initDateTime(31, mDec, 2000, 12, 00, 00, utc())
      let y = initDateTime(01, mJan, 2001, 00, 00, 00, utc())
      doAssert between(x, y) == 12.hours

    block:
      let x = initDateTime(31, mDec, 2000, 12, 00, 00, utc())
      let y = initDateTime(02, mJan, 2001, 00, 00, 00, utc())
      doAssert between(x, y) == 1.days + 12.hours

    block:
      let x = initDateTime(31, mDec, 1995, 00, 00, 00, utc())
      let y = initDateTime(01, mFeb, 2000, 00, 00, 00, utc())
      doAssert x + between(x, y) == y

    block:
      let x = initDateTime(01, mDec, 1995, 00, 00, 00, utc())
      let y = initDateTime(31, mJan, 2000, 00, 00, 00, utc())
      doAssert x + between(x, y) == y

    block:
      let x = initDateTime(31, mJan, 2000, 00, 00, 00, utc())
      let y = initDateTime(01, mFeb, 2000, 00, 00, 00, utc())
      doAssert x + between(x, y) == y

    block:
      let x = initDateTime(01, mJan, 1995, 12, 00, 00, utc())
      let y = initDateTime(01, mFeb, 1995, 00, 00, 00, utc())
      doAssert between(x, y) == 4.weeks + 2.days + 12.hours

    block:
      let x = initDateTime(31, mJan, 1995, 00, 00, 00, utc())
      let y = initDateTime(10, mFeb, 1995, 00, 00, 00, utc())
      doAssert x + between(x, y) == y

    block:
      let x = initDateTime(31, mJan, 1995, 00, 00, 00, utc())
      let y = initDateTime(10, mMar, 1995, 00, 00, 00, utc())
      doAssert x + between(x, y) == y
      doAssert between(x, y) == 1.months + 1.weeks

  block: # default DateTime https://github.com/nim-lang/RFCs/issues/211
    var num = 0
    for ai in Month: num.inc
    check num == 12

    var a: DateTime
    check a == DateTime.default
    check not a.isInitialized
    check $a == "Uninitialized DateTime"

    expect(AssertionDefect): discard getDayOfWeek(a.monthday, a.month, a.year)
    expect(AssertionDefect): discard a.toTime
    expect(AssertionDefect): discard a.utc()
    expect(AssertionDefect): discard a.local()
    expect(AssertionDefect): discard a.inZone(utc())
    expect(AssertionDefect): discard a + initDuration(seconds = 1)
    expect(AssertionDefect): discard a + initTimeInterval(seconds = 1)
    expect(AssertionDefect): discard a.isLeapDay
    expect(AssertionDefect): discard a < a
    expect(AssertionDefect): discard a <= a
    expect(AssertionDefect): discard getDateStr(a)
    expect(AssertionDefect): discard getClockStr(a)
    expect(AssertionDefect): discard a.format "yyyy"
    expect(AssertionDefect): discard a.format initTimeFormat("yyyy")
    expect(AssertionDefect): discard between(a, a)

  block: # inX procs
    doAssert initDuration(seconds = 1).inSeconds == 1
    doAssert initDuration(seconds = -1).inSeconds == -1
    doAssert initDuration(seconds = -1, nanoseconds = 1).inSeconds == 0
    doAssert initDuration(nanoseconds = -1).inSeconds == 0
    doAssert initDuration(milliseconds = 500).inMilliseconds == 500
    doAssert initDuration(milliseconds = -500).inMilliseconds == -500
    doAssert initDuration(nanoseconds = -999999999).inMilliseconds == -999

  block: # getIsoWeekAndYear
    doAssert getIsoWeekAndYear(initDateTime(04, mNov, 2019, 00, 00, 00)) == (isoweek: 45.IsoWeekRange, isoyear: 2019.IsoYear)
    doAssert initDateTime(dMon, 45, 2019.IsoYear, 00, 00, 00) == initDateTime(04, mNov, 2019, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(28, mDec, 2019, 00, 00, 00)) == (isoweek: 52.IsoWeekRange, isoyear: 2019.IsoYear)
    doAssert initDateTime(dSat, 52, 2019.IsoYear, 00, 00, 00) == initDateTime(28, mDec, 2019, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(29, mDec, 2019, 00, 00, 00)) == (isoweek: 52.IsoWeekRange, isoyear: 2019.IsoYear)
    doAssert initDateTime(dSun, 52, 2019.IsoYear, 00, 00, 00) == initDateTime(29, mDec, 2019, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(30, mDec, 2019, 00, 00, 00)) == (isoweek: 01.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dMon, 01, 2020.IsoYear, 00, 00, 00) == initDateTime(30, mDec, 2019, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(31, mDec, 2019, 00, 00, 00)) == (isoweek: 01.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dTue, 01, 2020.IsoYear, 00, 00, 00) == initDateTime(31, mDec, 2019, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mJan, 2020, 00, 00, 00)) == (isoweek: 01.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dWed, 01, 2020.IsoYear, 00, 00, 00) == initDateTime(01, mJan, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(02, mJan, 2020, 00, 00, 00)) == (isoweek: 01.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dThu, 01, 2020.IsoYear, 00, 00, 00) == initDateTime(02, mJan, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(05, mApr, 2020, 00, 00, 00)) == (isoweek: 14.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dSun, 14, 2020.IsoYear, 00, 00, 00) == initDateTime(05, mApr, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(06, mApr, 2020, 00, 00, 00)) == (isoweek: 15.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dMon, 15, 2020.IsoYear, 00, 00, 00) == initDateTime(06, mApr, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(10, mApr, 2020, 00, 00, 00)) == (isoweek: 15.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dFri, 15, 2020.IsoYear, 00, 00, 00) == initDateTime(10, mApr, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(12, mApr, 2020, 00, 00, 00)) == (isoweek: 15.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dSun, 15, 2020.IsoYear, 00, 00, 00) == initDateTime(12, mApr, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(13, mApr, 2020, 00, 00, 00)) == (isoweek: 16.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dMon, 16, 2020.IsoYear, 00, 00, 00) == initDateTime(13, mApr, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(15, mApr, 2020, 00, 00, 00)) == (isoweek: 16.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dThu, 16, 2020.IsoYear, 00, 00, 00) == initDateTime(16, mApr, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(17, mJul, 2020, 00, 00, 00)) == (isoweek: 29.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dFri, 29, 2020.IsoYear, 00, 00, 00) == initDateTime(17, mJul, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(19, mJul, 2020, 00, 00, 00)) == (isoweek: 29.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dSun, 29, 2020.IsoYear, 00, 00, 00) == initDateTime(19, mJul, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(20, mJul, 2020, 00, 00, 00)) == (isoweek: 30.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dMon, 30, 2020.IsoYear, 00, 00, 00) == initDateTime(20, mJul, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(23, mJul, 2020, 00, 00, 00)) == (isoweek: 30.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dThu, 30, 2020.IsoYear, 00, 00, 00) == initDateTime(23, mJul, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(31, mDec, 2020, 00, 00, 00)) == (isoweek: 53.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dThu, 53, 2020.IsoYear, 00, 00, 00) == initDateTime(31, mDec, 2020, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mJan, 2021, 00, 00, 00)) == (isoweek: 53.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dFri, 53, 2020.IsoYear, 00, 00, 00) == initDateTime(01, mJan, 2021, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(02, mJan, 2021, 00, 00, 00)) == (isoweek: 53.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dSat, 53, 2020.IsoYear, 00, 00, 00) == initDateTime(02, mJan, 2021, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(03, mJan, 2021, 00, 00, 00)) == (isoweek: 53.IsoWeekRange, isoyear: 2020.IsoYear)
    doAssert initDateTime(dSun, 53, 2020.IsoYear, 00, 00, 00) == initDateTime(03, mJan, 2021, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(04, mJan, 2021, 00, 00, 00)) == (isoweek: 01.IsoWeekRange, isoyear: 2021.IsoYear)
    doAssert initDateTime(dMon, 01, 2021.IsoYear, 00, 00, 00) == initDateTime(04, mJan, 2021, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mFeb, 2021, 00, 00, 00)) == (isoweek: 05.IsoWeekRange, isoyear: 2021.IsoYear)
    doAssert initDateTime(dMon, 05, 2021.IsoYear, 00, 00, 00) == initDateTime(01, mFeb, 2021, 00, 00, 00)

    doAssert getIsoWeekAndYear(initDateTime(01, mFeb, 2021, 01, 02, 03, 400_000_000, staticTz(hours=1))) == (isoweek: 05.IsoWeekRange, isoyear: 2021.IsoYear)
    doAssert initDateTime(dMon, 05, 2021.IsoYear, 01, 02, 03, 400_000_000, staticTz(hours=1)) == initDateTime(01, mFeb, 2021, 01, 02, 03, 400_000_000, staticTz(hours=1))

    doAssert getIsoWeekAndYear(initDateTime(01, mApr, +0001, 00, 00, 00)) == (isoweek: 13.IsoWeekRange, isoyear: 0001.IsoYear)
    doAssert initDateTime(dSun, 13, 0001.IsoYear, 00, 00, 00) == initDateTime(01, mApr, 0001, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mApr, +0000, 00, 00, 00)) == (isoweek: 13.IsoWeekRange, isoyear: 0000.IsoYear)
    doAssert initDateTime(dSat, 13, 0000.IsoYear, 00, 00, 00) == initDateTime(01, mApr, 0000, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mApr, -0001, 00, 00, 00)) == (isoweek: 13.IsoWeekRange, isoyear: (-0001).IsoYear)
    doAssert initDateTime(dThu, 13, (-0001).IsoYear, 00, 00, 00) == initDateTime(01, mApr, -0001, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mApr, -0002, 00, 00, 00)) == (isoweek: 14.IsoWeekRange, isoyear: (-0002).IsoYear)
    doAssert initDateTime(dWed, 14, (-0002).IsoYear, 00, 00, 00) == initDateTime(01, mApr, -0002, 00, 00, 00)
    doAssert getIsoWeekAndYear(initDateTime(01, mApr, -0753, 00, 00, 00)) == (isoweek: 14.IsoWeekRange, isoyear: (-0753).IsoYear)
    doAssert initDateTime(dMon, 14, (-0753).IsoYear, 00, 00, 00) == initDateTime(01, mApr, -0753, 00, 00, 00)

  block: # getWeeksInIsoYear
    doAssert getWeeksInIsoYear((-0014).IsoYear) == 52
    doAssert getWeeksInIsoYear((-0013).IsoYear) == 53
    doAssert getWeeksInIsoYear((-0012).IsoYear) == 52

    doAssert getWeeksInIsoYear((-0009).IsoYear) == 52
    doAssert getWeeksInIsoYear((-0008).IsoYear) == 53
    doAssert getWeeksInIsoYear((-0007).IsoYear) == 52

    doAssert getWeeksInIsoYear((-0003).IsoYear) == 52
    doAssert getWeeksInIsoYear((-0002).IsoYear) == 53
    doAssert getWeeksInIsoYear((-0001).IsoYear) == 52

    doAssert getWeeksInIsoYear(0003.IsoYear) == 52
    doAssert getWeeksInIsoYear(0004.IsoYear) == 53
    doAssert getWeeksInIsoYear(0005.IsoYear) == 52

    doAssert getWeeksInIsoYear(1653.IsoYear) == 52
    doAssert getWeeksInIsoYear(1654.IsoYear) == 53
    doAssert getWeeksInIsoYear(1655.IsoYear) == 52

    doAssert getWeeksInIsoYear(1997.IsoYear) == 52
    doAssert getWeeksInIsoYear(1998.IsoYear) == 53
    doAssert getWeeksInIsoYear(1999.IsoYear) == 52

    doAssert getWeeksInIsoYear(2008.IsoYear) == 52
    doAssert getWeeksInIsoYear(2009.IsoYear) == 53
    doAssert getWeeksInIsoYear(2010.IsoYear) == 52

    doAssert getWeeksInIsoYear(2014.IsoYear) == 52
    doAssert getWeeksInIsoYear(2015.IsoYear) == 53
    doAssert getWeeksInIsoYear(2016.IsoYear) == 52

  block: # parse and generate iso years
    # short calendar week with text
    parseTest("KW 23 2023", "'KW' VV GGGG",
      "2023-06-05T00:00:00Z", 155)
    parseTest("KW 5 2023", "'KW' V GGGG",
      "2023-01-30T00:00:00Z", 29)
    parseTest("KW 05 23 Saturday", "'KW' V GG dddd",
      "2023-02-04T00:00:00Z", 34)
    parseTest("KW 53 20 Fri", "'KW' VV GG ddd",
      "2021-01-01T00:00:00Z", 0)

    parseTestExcp("KW 23", "'KW' VV") # no year
    parseTestExcp("KW 23", "'KW' V") # no year
    parseTestExcp("KW 23", "'KW' GG") # no week
    parseTestExcp("KW 2023", "'KW' GGGG") # no week
    
    var dt = initDateTime(5, mJan, 2023, 0, 0, 0, utc())
    check dt.format("V") == "1"
    check dt.format("VV") == "01"
    check dt.format("GG") == "23"
    check dt.format("GGGG") == "2023"
    check dt.format("dddd 'KW'V GGGG") == "Thursday KW1 2023"

  block: # Can be used inside gcsafe proc
    proc test(): DateTime {.gcsafe.} =
      result = "1970".parse("yyyy")
    doAssert test().year == 1970

  block: # test FormatLiterals
    # since #23861
    block:
      let dt = dateTime(2024, mJul, 21, 17, 01, 02, 123_321_123, utc())
      check dt.format("ss.fff") == "02.123"
      check dt.format("fff.ffffff") == "123.123321"
    block:
      let dt = parse("2024.07.21", "yyyy.MM.dd")
      check dt.year == 2024
      check dt.month == mJul
      check dt.monthday == 21
