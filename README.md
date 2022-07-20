# NAME

aio - Asynchronous IO Helpers for Tcl

# SYNOPSIS

**package require aio** ?1.0?

**aio waitfor** *what* *chan* ?*seconds*?

**aio coro\_vwait** *varname* ?*seconds*?

**aio gets** *chan* ?*seconds*?

**aio read** *chan* *length* ?*seconds*?

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
    errorcode **AIO TIMEOUT CORO\_VWAIT** *varname*. Can only be called
    from a coroutine context.
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
    }}]
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

chan configure $sock -blocking no -buffering none \
    -encoding utf-8 -translation lf -eofchar {}

# Wait up to 5 seconds for the socket to connect
aio waitfor writable $sock 5.0

set msg "Some message containing\nnewlines and some \u306f unicode"
puts -nonewline $sock [string length $msg]\n$msg
puts "Response from server: [aio gets $sock 10.0]"

close $sock
```

# LICENSE

This package Copyright 2022 Cyan Ogilvie, and is made available under
the same license terms as the Tcl Core.
