# issue #12405

import std/[marshal, streams, times, tables, os, assertions]

type AiredEpisodeState * = ref object
    airedAt * : DateTime
    tvShowId * : string
    seasonNumber * : int
    number * : int
    title * : string

type ShowsWatchlistState * = ref object
    aired * : seq[AiredEpisodeState]

type UiState * = ref object
    shows: ShowsWatchlistState

# Helpers to marshal and unmarshal
proc load * ( state : var UiState, file : string ) =
    var strm = newFileStream( file, fmRead )

    strm.load( state )

    strm.close()

proc store * ( state : UiState, file : string ) =
    var strm = newFileStream( file, fmWrite )

    strm.store( state )

    strm.close()

# 1. We fill the state initially
var state : UiState = UiState( shows: ShowsWatchlistState( aired: @[] ) )

# VERY IMPORTANT: For some reason, small numbers (like 2 or 3) don't trigger the bug. Anything above 7 or 8 on my machine triggers though
for i in 0..30:
    var episode = AiredEpisodeState( airedAt: now(), tvShowId: "1", seasonNumber: 1, number: 1, title: "string" )

    state.shows.aired.add( episode )

# 2. Store it in a file with the marshal module, and then load it back up
store( state, "tmarshalsegfault_data" )
load( state, "tmarshalsegfault_data" )
removeFile("tmarshalsegfault_data")

# 3. VERY IMPORTANT: Without this line, for some reason, everything works fine
state.shows.aired[ 0 ] = AiredEpisodeState( airedAt: now(), tvShowId: "1", seasonNumber: 1, number: 1, title: "string" )

# 4. And formatting the airedAt date will now trigger the exception
for ep in state.shows.aired:
    let x = $ep.seasonNumber & "x" & $ep.number & " (" & $ep.airedAt & ")"
    let y = $ep.seasonNumber & "x" & $ep.number & " (" & $ep.airedAt & ")"
    doAssert x == y
