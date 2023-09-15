# NAME

aio - Asynchronous IO Helpers for Tcl

# SYNOPSIS

**package require aio** ?1.6?

**aio waitfor** *what* *chan* ?*seconds*?

**aio coro\_vwait** *varname* ?*seconds*?

**aio gets** *chan* ?*seconds*?

**aio read** *chan* *length* ?*seconds*?

**aio coro\_sleep** *seconds*

# DESCRIPTION

This module provides a collection of helpers for performing asynchronous
IO in a blocking style, using coroutines and vwaits (when not called in
a coroutine context). Tcl provides excellent event-based non-blocking IO
capabilities, but in many situations the control flow is easier to
reason about when written in a linear, blocking fashion. **aio** bridges
this gap by presenting an interface that behaves like blocking reads and
writes (with timeouts) from the perspective of the calling code, but
operates on top of the native Tcl event driven IO under the hood and
never blocks (provided the channels it is given are in non-blocking
mode).

# COMMANDS

  - **aio waitfor** *what* *chan* ?*seconds*?  
    Block the caller until *chan* becomes readable or writable as
    specified by *what*, which must be a list containing at least one of
    “readable” or “writable”, or the timeout in fractional seconds given
    by *seconds* occurs. If *seconds* is a blank string or not
    specified, no timeout applies. If a timeout occurs an exception is
    thrown with the errorcode **AIO TIMEOUT** *what*.
  - **aio coro\_vwait** *varname* ?*seconds*?  
    Block the caller until *varname* is written to, or *seconds*
    fractional seconds elapse, if *seconds* is specified and not a blank
    string. If a timeout occurs an exception is thrown with the
    errorcode **AIO TIMEOUT CORO\_VWAIT** *varname*. The value of
    *varname* when it is first set is returned, which may be different
    to its current value, because **coro\_vwait** only returns after the
    event loop is reached after the code that set the variable. Can only
    be called from a coroutine context.
  - **aio gets** *chan* ?*seconds*?  
    Blocks the caller until a line is read from *chan*, or *seconds*
    fractional seconds elapse, if *seconds* is specified and not a blank
    string. The line is returned if there is no timeout, or an exception
    is thrown with the errorcode **AIO TIMEOUT readable** if there was.
    If the channel is closed while waiting for a complete line an
    exception is thrown with the errorcode **AIO CLOSED**.
  - **aio read** *chan* *length* ?*seconds*?  
    Blocks the caller until *length* characters are read from *chan*, or
    *seconds* fractional seconds elapse, if *seconds* is specified and
    not a blank string. The characters read are returned or an exception
    is thrown with the errorcode **AIO TIMEOUT readable** if the read
    timed out. If the channel is closed while waiting for *length*
    characters an exception is thrown with the errorcode **AIO CLOSED**.
  - **aio coro\_sleep** *seconds*  
    Yields the current coroutine for *seconds* seconds, taking care to
    clean up the after event if the coroutine is deleted before it
    fires.

# EXAMPLES

Simple TCP server that starts a coroutine to handle each new connection,
and reads frames off the connection consisting of a line-delimited
character count followed by that many characters:

``` tcl
package require aio

proc conn_handler {sock ip port} {
    set cleanup [list apply {{sock args} {
        if {$sock in [chan names]} {
            close $sock
        }
    }} $sock]
    trace add command [info coroutine] delete $cleanup

    # It's usually more sensible to implement framing
    # in a stream protocol like TCP in binary mode,
    # but this example sets the channel mode to utf-8
    # to demonstrate that it is possible.  $len in
    # this case refers to the number of characters,
    # not bytes in the frame payload.
    chan configure $sock -blocking no -buffering none \
        -encoding utf-8 -translation lf -eofchar {}

    try {
        while 1 {
            set len     [aio gets $sock 10.0]
            set frame   [aio read $sock $len 10.0]
            puts "Got frame:\n$frame"
            puts $sock "acknowledge receipt of [string length $frame] characters"
        }
    } trap {AIO TIMEOUT} {errmsg options} {
        set what    [lindex [dict get $options -errorcode] 2]
        puts stderr "Timeout waiting for $what from $ip:$port"
    } trap {AIO CLOSED} {errmsg options} {
        puts stderr "Connection from $ip:$port lost"
    }
}

proc accept {sock ip port} {
    coroutine handle_$sock conn_handler $sock $ip $port
}

set listen  [socket -server accept 0]
lassign [chan configure $listen -sockname] \
    listen_addr listen_hostname listen_port
puts "Listening on $listen_addr:$listen_port"
vwait forever
```

Corresponding client:

``` tcl
package require aio

lassign $argv ip port

set sock    [socket -async $ip $port]

chan configure $sock -blocking yes -buffering none \
    -encoding utf-8 -translation lf -eofchar {}

# Wait up to 5 seconds for the socket to connect
aio waitfor writable $sock 5.0
chan configure $sock -blocking no

set msg "Some message containing\nnewlines and some \u306f unicode"
puts -nonewline $sock [string length $msg]\n$msg
puts "Response from server: [aio gets $sock 10.0]"

close $sock
```

Watch for changes in a global variable from multiple coroutines:

``` tcl
package require aio

proc watcher {} {
    global stats

    while 1 {
        set res [aio coro_vwait stats]
        puts "[clock microseconds] [info coroutine] got stats: $res"
    }
}

coroutine coro_1 watcher
coroutine coro_2 watcher

set loops   0
while 1 {
    puts "[clock microseconds] poll setting stats"
    set stats "stats, updated: [clock microseconds]"
    if {[incr loops] == 3} break

    puts "[clock microseconds] poll waiting"
    after 1000 {set delay 1}
    vwait delay
}
puts "[clock microseconds] draining pending events before exiting"
update
```

Produces output like:

    1658393851230938 poll setting stats
    1658393851230966 poll waiting
    1658393851230973 ::coro_2 got stats: stats, updated: 1658393851230953
    1658393851230978 ::coro_1 got stats: stats, updated: 1658393851230953
    1658393852231263 poll setting stats
    1658393852231317 poll waiting
    1658393852231329 ::coro_1 got stats: stats, updated: 1658393852231284
    1658393852231348 ::coro_2 got stats: stats, updated: 1658393852231284
    1658393853231838 poll setting stats
    1658393853231912 draining pending events before exiting
    1658393853231929 ::coro_2 got stats: stats, updated: 1658393853231860
    1658393853231946 ::coro_1 got stats: stats, updated: 1658393853231860

# COMPLETELY NON-BLOCKING NETWORKING

One reason to reach for tools like these is to achieve single-threaded
non-blocking network servers and clients, but in that case it’s
important to ensure that the thread can never block on IO (not servicing
events) or it will stave all the other sources and sinks. Two common but
possibly unexpected sources of IO blocking in Tcl (even when all
channels are set to non-blocking mode) are client socket establishment
and DNS resolution. The first of these can be addressed with the
**-async** flag to the **socket** command, and then waiting in the event
loop for the connect to complete with **aio waitfor writable** (channel
must be in blocking mode for this). The second (DNS resolution delays)
can be addressed with the [resolve
package](https://github.com/cyanogilvie/resolve) by doing the name
lookup first in a non-blocking way and then handing the IP to
**socket**.

# LICENSE

This package Copyright 2023 Cyan Ogilvie, and is made available under
the same license terms as the Tcl Core.
