import std/[osproc, os, times]

block: # bug #5091
    when defined(linux):
        const filename = "false"
        var p = startProcess(filename, options = {poStdErrToStdOut, poUsePath})
        os.sleep(1000) # make sure process has exited already

        let atStart = getTime()
        const msWait = 2000

        try:
            discard waitForExit(p, msWait)
        except OSError:
            discard

        # check that we don't have to wait msWait milliseconds
        doAssert(getTime() <  atStart + milliseconds(msWait))

block: # bug #23825

    # the sleep command might not be available in all Windows installations

    when defined(linux):

        var thr: array[0..99, Thread[int]]

        proc threadFunc(i: int) {.thread.} =
            let sleepTime = float(i) / float(thr.len + 1)
            doAssert sleepTime < 1.0
            let p = startProcess("sleep", workingDir = "", args = @[$sleepTime], options = {poUsePath, poParentStreams})
            # timeout = 1_000_000 seconds ~= 278 hours ~= 11.5 days
            doAssert p.waitForExit(timeout=1_000_000_000) == 0

        for i in low(thr)..high(thr):
            createThread(thr[i], threadFunc, i)

        joinThreads(thr) 
