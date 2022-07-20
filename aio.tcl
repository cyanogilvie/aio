namespace eval ::aio {
	namespace export *
	namespace ensemble create -prefixes no -map {
		waitfor		waitfor
		coro_vwait	coro_vwait
		gets		_gets
		read		_read
    }

	variable _wait_for_res
	array set _wait_for_res	{}

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
				set timeout_afterid	[after [expr {max(0, int($seconds * 1000))}] [list {*}$ev_prefix timeout]]
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
        }
		uplevel 1 [list trace add variable $var write $coro]
		lassign [yieldto return -level 0] ev
		uplevel 1 [trace remove variable $var write $coro]
        if {[info exists afterid]} {after cancel $afterid}
        if {$ev eq "timeout"} {
            throw [list AIO TIMEOUT CORO_VWAIT $var] "Timeout waiting for a write of $var"
        }
	}

	#>>>
	proc _gets {chan {seconds {}}} { #<<<
		if {$seconds ne {}} {
			set horizon	[expr {[clock seconds] + $seconds}]
		}
		while 1 {
			set line	[gets $chan]

			if {[chan eof $chan]} {
				throw {AIO CLOSED} "$chan was closed while waiting for a line"
			}

			if {[chan blocked $chan]} {
				if {[info exists horizon]} {
					waitfor readable $chan [expr {$horizon - [clock seconds]}]
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
			set horizon	[expr {[clock seconds] + $seconds}]
		}
		set buf	{}
		while {[set remain [expr {$length - [string length $buf]}]] > 0} {
			append buf	[read $chan $remain]

			if {[chan eof $chan]} {
				throw {AIO CLOSED} "$chan was closed while waiting for a line"
			}

			if {[chan blocked $chan]} {
				if {[info exists horizon]} {
					waitfor readable $chan [expr {$horizon - [clock seconds]}]
				} else {
					waitfor readable $chan
				}
			}
		}
		set buf
	}

	#>>>
}

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
