package require Tcl 8.6	;# For coroutine support

namespace eval ::aio {
	namespace export *
	namespace ensemble create -prefixes no -map {
		waitfor		waitfor
		coro_vwait	coro_vwait
		gets		_gets
		read		_read
    }

	variable _waitfor_res
	array set _waitfor_res	{}

	proc waitfor {what chan {seconds {}}} { #<<<
		variable _waitfor_seq
		variable _waitfor_res

		set my_seq	[incr _waitfor_seq]

		set cleanup [list {chan afterid my_seq args} {
			variable _waitfor_res
			catch {chan event $chan readable {}}
			catch {chan event $chan writable {}}
			after cancel $afterid
			unset -nocomplain _waitfor_res($my_seq)
		} [namespace current]]

		set timeout_afterid	""
		try {
			if {[info coroutine] ne ""} {
				set ev_prefix	[list [info coroutine]]
				set wait_cmd	{set _waitfor_res($my_seq)	[yield]}
			} else {
				set ev_prefix	[list set   [namespace which -variable _waitfor_res]($my_seq)]
				set wait_cmd	[list vwait [namespace which -variable _waitfor_res]($my_seq)]
			}

			if {$seconds ne ""} {
				#puts stderr "waitfor setting timeout for [expr {max(0, int($seconds * 1000))}] ms"
				set timeout_afterid	[after [expr {max(0, int(ceil($seconds * 1000)))}] [list {*}$ev_prefix timeout]]
			}
            foreach e $what {
                if {$e ni {readable writable}} {error "Invalid event \"$e\": must be readable or writable"}
            }
			if {"readable" in $what} {
				chan event $chan readable [list {*}$ev_prefix readable]
			}
			if {"writable" in $what} {
				chan event $chan writable [list {*}$ev_prefix writable]
			}

			if {[info coroutine] ne ""} {
				set coro_cleanup_command	[list apply $cleanup $chan $timeout_afterid $my_seq]
				trace add command [info coroutine] delete $coro_cleanup_command
			}

			#puts stderr "Waiting for readable on $chan: $wait_cmd <[info frame -1]>"
			try $wait_cmd
			#puts stderr "Got readable on $chan"

			#puts stderr "waitfor outcome: ($_waitfor_res($my_seq))"
			switch -- $_waitfor_res($my_seq) {
				readable {return readable}
				writable {return writable}
				timeout {
					throw [list AIO TIMEOUT [lsort -unique $what]] "Timeout waiting for $what"
				}
				default {
					throw {AIO PANIC} "Unexpected status waiting for data: ($_waitfor_res($my_seq))"
				}
			}
		} finally {
			if {[info exists coro_cleanup_command] && [info coroutine] ne {}} {
				trace remove command [info coroutine] delete $coro_cleanup_command
			}

			apply $cleanup $chan $timeout_afterid $my_seq
		}
	}

	#>>>
	proc coro_vwait {var {seconds {}}} { #<<<
		set coro	[list [info coroutine] set]
        if {$seconds ne {}} {
            set afterid [after [expr {max(0, int($seconds * 1000))}] [list [info coroutine] timeout]]
        } else {
			set afterid	""
		}
		set fqvar	[uplevel 1 [list namespace which -variable $var]]

		set cleanup	[list apply {{fqvar coro afterid oldname newname op} {
			after cancel $afterid
			trace remove variable $fqvar write $coro
		}} $fqvar $coro $afterid]
		trace add command [info coroutine] delete $cleanup

		trace add variable $fqvar write $coro
		lassign [yieldto return -level 0] ev n1 n2 op
		trace remove variable $fqvar write $coro
		trace remove command [info coroutine] delete $cleanup
        if {[info exists afterid]} {after cancel $afterid}
        if {$ev eq "timeout"} {
            throw [list AIO TIMEOUT CORO_VWAIT $var] "Timeout waiting for a write of $var"
        }
		if {$n2 ne {}} {append n1 ($n2)}
		upvar 1 $n1 lvar
		set val	$lvar

		# Defer returning from coro_vwait so that an error in the caller's following code doesn't
		# throw a {TCL WRITE VARNAME} exception on the set that triggered the trace
		after 0 [list [info coroutine]]
		yield

		set val	;# Return the value of the var at the time that the trace was triggered
	}

	#>>>
	proc _gets {chan {seconds {}}} { #<<<
		set start	[clock microseconds]
		if {$seconds ne {}} {
			set horizon	[expr {[clock microseconds] + $seconds*1e6}]
		}
		while 1 {
			set line	[gets $chan]
			#puts stderr "[expr {[clock microseconds] - $start}] aio gets back from gets \$chan, line: ($line), eof: [eof $chan], blocked: [chan blocked $chan]"

			if {[chan eof $chan]} {
				throw {AIO CLOSED} "$chan was closed while waiting for a line"
			}

			if {[chan blocked $chan]} {
				if {[info exists horizon]} {
					waitfor readable $chan [expr {($horizon - [clock microseconds])/1e6}]
				} else {
					waitfor readable $chan
				}
				continue
			}

			return $line
		}
	}

	#>>>
	proc _read {chan length {seconds {}}} { #<<<
		if {$seconds ne {}} {
			set horizon	[expr {[clock microseconds] + $seconds*1e6}]
		}
		set buf	{}
		while {[set remain [expr {$length - [string length $buf]}]] > 0} {
			append buf	[read $chan $remain]

			if {[chan eof $chan]} {
				throw {AIO CLOSED} "$chan was closed while waiting for a read of $length chars"
			}

			if {[chan blocked $chan]} {
				if {[info exists horizon]} {
					waitfor readable $chan [expr {($horizon - [clock microseconds])/1e6}]
				} else {
					waitfor readable $chan
				}
			}
		}
		set buf
	}

	#>>>
	proc coro_sleep seconds { #<<<
		set afterid	[after [expr {int(ceil($sec * 1000))}] [list [info coroutine]]]
		set cleanup	[list apply {{afterid old new op} {after cancel $afterid}} $afterid]
		trace add command [info coroutine] delete $cleanup
		try {
			yield
		} finally {
			trace remove command [info coroutine] delete $cleanup
		}
	}

	#>>>
}

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
