# Terminal capabilities.  Subcommands return the escape sequence to output to the terminal

package require parse_args

namespace eval ::tty {
	namespace export *
	namespace ensemble create -prefixes no

	variable re	{}
	dict set re	soh_to_sot		{(?:\x01[^\x02]*?\x02)+}
	dict set re esc_seq			{(?:\e\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e])+}
	dict set re non_print		[dict get $re soh_to_sot]|[dict get $re esc_seq]
	#dict set re print			{(?:.(?!\x01|\e\[))*}
	dict set re print			{[^\e\x01]*}
	dict set re print,non_print	([dict get $re print])([dict get $re non_print])?

	namespace eval helpers { #<<<
		variable cache	{}

		proc _cache {key script} { #<<<
			variable cache

			if {![dict exists $cache $key]} {
				dict set cache $key [uplevel 1 $script]
			}

			dict get $cache $key
		}

		#>>>
		proc cache args { # cache tput output <<<
			_cache $args {
				try {
					exec tput {*}$args
				} trap CHILDSTATUS {errmsg options} {
					#puts stderr "tput $args failed: $errmsg"
					return -options $options $errmsg
				}
			}
		}

		#>>>
		proc check_bool args { # cache exit-status signalled boolean <<<
			_cache $args {
				try {
					exec tput {*}$args
				} on ok {} {
					return -level 0 true
				} trap {CHILDSTATUS} {} {
					return -level 0 false
				}
			}
		}

		#>>>
		proc updatesize {} { # called when we receive SIGWINCH (the term size has changed <<<
			variable cache

			lassign [exec stty size] lines columns
			set ::env(LINES)	$lines
			set ::env(COLUMNS)	$columns

			dict unset cache cols
			dict unset cache lines

			dict for {name cb} $::tty::resize_cbs {
				try {
					uplevel #0 $cb
				} on error {errmsg options} {
					after idle [list {*}[interp bgerror {}] $errmsg $options]
				}
			}
		}

		#>>>
	}

	#>>>
	namespace path {
		::parse_args
		helpers
		::tcl::mathop
	}

	proc set_mode_cursor {}				{cache smcup}
	proc reset_mode_cursor {}			{cache rmcup}
	proc clear {}						{cache clear}
	proc goto {l c}						{cache cup $l $c}
	proc clear_to_end {}				{cache ed}
	proc goto_statusline {{c 0}}		{cache tsl $c}
	proc set_scroll_region {from to}	{cache csr $from $to}
	proc delete_lines count				{cache dl $count}
	proc clear_to_end_of_line {}		{cache el}
	proc graphchars {}					{cache acsc}
	proc repeat {char count} { #<<<
		#cache rep $char $count
		string repeat $char $count
	}

	#>>>
	proc goto_last_line {} { #<<<
		#cache ll
		goto [get lines] 0
	}

	#>>>
	variable resize_cbs	{}
	proc on_resize {name cb} { # Register callback $cb to run when the term size changes, or remove it if $cb eq "" <<<
		variable resize_cbs
		if {$cb eq ""} {
			dict unset resize_cbs $name
		} else {
			dict set resize_cbs $name $cb
		}
	}

	#>>>
	proc save_cursor script { #<<<
		tty write [cache sc]
		try {
			uplevel 1 $script
		} finally {
			tty write [cache rc]
		}
	}

	#>>>

	proc setup {} { #<<<
		package require tclsignal
		signal add SIGWINCH ::tty::helpers::updatesize
		updatesize
		signal add SIGTERM ::exit
		signal add SIGINT ::exit
        #tty write [tty set_mode_cursor]

		# Arrange to have rmcup run at exit
		if {[llength [info commands ::tty::_exit]] == 0} {
			rename ::exit ::tty::_exit
			proc ::exit {{rc 0}} {
				tty write [tty reset_mode_cursor]
				tailcall ::tty::_exit $rc
			}
		}
	}

	#>>>
	proc write chars { #<<<
		puts -nonewline stdout $chars; flush stdout
	}

	#>>>

	namespace eval get { # Read values from the terminal: term lines, cols, etc <<<
		namespace ensemble create -prefixes no
		namespace export *
		namespace path {::tty::helpers}

		proc columns {}		{cache cols}
		proc lines {}		{cache lines}
	}

	#>>>
	namespace eval can { # Query boolean properties from the terminal <<<
		namespace ensemble create -prefixes no
		namespace export *
		namespace path {::tty::helpers}

		proc overstrike {}	{check_bool os}
		proc statusline {}	{check_bool hs}
	}

	#>>>

	proc strip_ansi string { # Return a string, stipped of ANSI control sequences <<<
		variable re
		regsub -all [dict get $re non_print] $string {}
	}

	#>>>
	proc printable_length string { # Return the count of printable characters <<<
		string length [strip_ansi $string]
	}

	#>>>
	proc c args { #<<<
		set map {
			black		30
			red			31
			green		32
			yellow		33
			blue		34
			purple		35
			cyan		36
			white		37
			bg_black	40
			bg_red		41
			bg_green	42
			bg_yellow	43
			bg_blue		44
			bg_purple	45
			bg_cyan		46
			bg_white	47
			inverse		7
			bold		5
			underline	4
			bright		1
			norm		0
		}
		join [lmap t $args {
			if {![dict exists $map $t]} continue
			return -level 0 \1\x1B\[[dict get $map $t]m\2
		}] {}
	}

	#>>>
	proc colour args { #<<<
		set colours	[lrange $args 0 end-1]
		set script	[lindex $args end]
		string cat [c {*}$args] [uplevel 1 $script] [c norm]
	}

	#>>>
	proc colour_format {formatString args} { # Wrapper around ::format that adjusts string width modifiers for non-printing escape sequences <<<
		set orig_args	$args

		set parts	{}
		foreach {all preamble position qualifiers type} [regexp -all -inline {([^%]*)(?:%(?:([0-9]+)\$)?(.*?(?:ll|h|l)?)([a-z%]))?} $formatString] {
			if {$type eq "%"} {
				append hold	$all
				continue
			}
			if {[info exists hold]} {
				set preamble	$hold$preamble
				unset hold
			}
			lappend parts [list $preamble $position $qualifiers $type]
		}
		if {[info exists hold]} {
			lappend parts [list $all {} {} {}]
		}

		# Enforce: if any conversions are positional, all must be:
		set has_position	[llength [lsearch -all -exact -not -index 1 $parts {}]]
		if {$has_position != 0 && $has_position != [llength $parts]} {
			# Delegate to ::format to produce the error
			tailcall format $formatString {*}$args
		}

		# Special case: no "%" in formatString
		if {[llength $parts] == 1 && [lindex $parts 0 3] eq ""} {
			tailcall format $formatString {*}$args
		}

		# Find all string formats, matched with input args and adjust the format width specifier to compensate for the non-printing characters
		set adjusted_formatString	""
		set argp					0
		foreach part $parts {
			lassign $part preamble position qualifiers type

			if {![regexp {^([-+ 0#]*)?(?:([0-9]*|\*)(?:\.([0-9]+|\*))?)?(ll|l|h)?$} $qualifiers - flags minsize maxsize sizemod]} {
				# Can't parse qualifiers for conversion, delegate the error generation
				tailcall format $formatString {*}$args
			}

			# Resolve the arg(s) consumed by this conversion <<<
			set position_ofs	0

			unset -nocomplain minsize_val
			if {$minsize eq "*"} {
				# Next arg contains size
				if {$position eq ""} {
					set minsize_arg_idx	$argp
					incr argp
				} else {
					set minsize_arg_idx	[expr {$position-1 + $position_ofs}]
					incr position_ofs
				}
				set minsize_val	[lindex $args $minsize_arg_idx]
			} elseif {$minsize ne ""} {
				set minsize_val	$minsize
			}

			# Precision part: for strings this is the max field width
			unset -nocomplain maxsize_val
			if {$maxsize eq "*"} {
				# Next arg contains size
				if {$position eq ""} {
					set maxsize_arg_idx	$argp
					incr argp
				} else {
					set maxsize_arg_idx	[expr {$position-1 + $position_ofs}]
					incr position_ofs
				}
				set maxsize_val	[lindex $args $maxsize_arg_idx]
			} elseif {$maxsize ne ""} {
				set maxsize_val	$maxsize
			}

			if {$position eq ""} {
				set arg	[lindex $args $argp]
				incr argp
			} else {
				set arg	[lindex $args [expr {$position-1 + $position_ofs}]
			}
			# Resolve the arg(s) consumed by this conversion >>>

			#puts stderr [join [lmap v {
			#	preamble position qualifiers type
			#	flags minsize minsize_val maxsize maxsize_val sizemod
			#} {
			#	if {[info exists $v]} {
			#		format {%12s: (%s)} $v [set $v]
			#	} else {
			#		format {%12s: --} $v
			#	}
			#}] \n]

			if {$type eq "s"} {
				set diff	[expr {[string length $arg] - [printable_length $arg]}]
				#puts stderr "len: [string length $arg], printable_len: [printable_length $arg], diff: $diff"

				if {[info exists minsize_val]} {
					incr minsize_val $diff
					if {$minsize eq "*"} {
						lset args $minsize_arg_idx $minsize_val
					} else {
						set minsize	$minsize_val
					}
				}

				if {[info exists maxsize_val]} {
					incr maxsize_val $diff
					if {$maxsize eq "*"} {
						lset args $maxsize_arg_idx $maxsize_val
					} else {
						set maxsize	$maxsize_val
					}
				}
			}

			set qualifiers			$flags$minsize
			if {$maxsize ne ""} {
				append qualifiers	.$maxsize
			}
			append qualifiers		$sizemod

			append adjusted_formatString		$preamble%
			if {$position ne ""} {
				append adjusted_formatString	$position\$
			}
			append adjusted_formatString		$qualifiers$type
		}

		#puts stderr "Adjusted args:\n\t[join [lmap orig $orig_args arg $args {
		#	format {(%s) -> (%s)} $orig $arg
		#}] \n\t]"
		#puts stderr "tty colour_format ($formatString) -> ($adjusted_formatString)"
		tailcall format $adjusted_formatString {*}$args
	}

	#>>>
	proc colour_clipped {string cliplen} { #<<<
		variable re

		set acc		0
		set clipped	{}
		foreach {- print non_print} [regexp -all -inline [dict get $re print,non_print] $string] {
			set remain	[- $cliplen $acc]
			set len		[string length $print]
			if {$remain < $len} {
				set print	[string range $print 0 $remain-1]
				#tty write "Clipped at acc: $acc, len: $len, remain: $remain, cols: [tty get columns], clipped printable len: [tty printable_length $clipped], print: ([tty printable_length $print])\n"
				append clipped	$print[c norm]
				break
			}
			#tty write "non_print: [regexp -all -inline .. [binary encode hex $non_print]]"
			append clipped	$print $non_print
			#append clipped	$print
			incr acc $len
			#tty write "acc: $acc, clipped: [tty printable_length $clipped]\n"
		}
		set clipped
	}

	#>>>
	proc table args { #<<<
		parse_args $args {
			-data			{-required -# {list of rows, which are dictionaries mapping key->val}}
			-col_sep		{-default { | }}
			-columns		{-required}
			-formatters		{-default {}}
			-border_colour	{-default white}
		}

		set col_sep		[colour {*}$border_colour {set col_sep}]
		set titles		[lmap e $columns {colour white {lindex $e 0}}]
		set alignments	[lmap e $columns {lindex $e 2}]

		set rows		[list $titles]
		foreach rowdata $data {
			set cells	{}
			set a		{}
			foreach e $columns {
				lassign $e title key align adjust
				set v	[dict get $rowdata $key]
				if {[dict exists $formatters $key]} {
					try {
						apply [dict get $formatters $key] $v
					} on ok cell_val {
					} on error {errmsg options} {
						set error_prefix	"Error formatting key \"$key\": "
						dict set options -errorinfo $error_prefix[dict get $options -errorinfo]
						return -options $options $error_prefix$errmsg
					}
				} else {
					set cell_val	$v
				}
				lappend cells $cell_val
			}
			lappend rows $cells
		}

		# Find the max width of each column
		set cell_lengths	[lmap row $rows {
			lmap cell $row {
				tty printable_length $cell
			}
		}]
		#:wputs stderr "cell_lengths:\n\t[join [lmap row $cell_lengths {set row}] \n\t]"

		set max_lengths	{}
		for {set i 0} {$i < [llength $columns]} {incr i} {
			lappend max_lengths	[tcl::mathfunc::max {*}[lmap row $cell_lengths {lindex $row $i}]]
		}
		set sep_size	[expr {([llength $columns]-1) * [tty printable_length $col_sep]}]
		set total_max	[+ {*}$max_lengths $sep_size]

		set available_width		[tty get columns]
		set column_adjustments	[lrepeat [llength $columns] 0]
		if {$available_width - $total_max < 0} { # Figure out where to squeeze <<<
			set i	-1
			set takers	[lmap e $columns {
                parse_args [lindex $e 3] {
                    -size   {-default grow}
                } colopts
				incr i
				if {[dict get $colopts size] ni {shrink both}} continue
				set i
			}]
			if {[llength $takers] == 0} {
				# No takers, distribute over all
				for {set i} {$i < [llength $columns]} {incr i} {lappend takers $i}
			}
			#>>>
		} elseif {$available_width - $total_max > 0} { # Figure out how to distribute the extra <<<
			set i	-1
			set takers	[lmap e $columns {
                parse_args [lindex $e 3] {
                    -size   {-default grow}
                } colopts
				incr i
				if {[dict get $colopts size] ni {grow both}} continue
				set i
			}]
			if {[llength $takers] == 0} {
				# No takers, distribute over all
				for {set i} {$i < [llength $columns]} {incr i} {lappend takers $i}
			}
			#>>>
		} else {
			set takers	{}
		}
		set acc	0
		if {[llength $takers]} {
			set inc	[expr {($available_width - $total_max) / double([llength $takers])}]
		} else {
			set inc	0
		}
		foreach taker $takers {
			set acc							[+ $acc $inc]
			lset column_adjustments $taker	[expr {int($acc)}]
			set acc							[expr {fmod($acc, 1.0)}]
		}

		set write_buf	{}
		set lines	[llength $data]

		set format	[join [lrepeat [llength $columns] %s] $col_sep]
		set	line	0
		foreach row $rows {
			set row_txt [tty colour_format $format {*}[lmap \
				cell			$row \
				content_width	$max_lengths \
				adjustment		$column_adjustments \
				align			$alignments \
			{
				set colwidth	[+ $content_width $adjustment]
				switch -exact -- $align {
					left	{
						#set padded	[tty colour_format %-${colwidth}.${colwidth}s $cell]
						set leftpad		0
						set rightpad	[- $colwidth [tty printable_length $cell]]
					}
					right	{
						#set padded [tty colour_format %${colwidth}.${colwidth}s  $cell]
						set rightpad	0
						set leftpad		[- $colwidth [tty printable_length $cell]]
					}
					centre {
						set extra		[- $colwidth [tty printable_length $cell]]
						set leftpad		[expr {int($extra/2.0)}]
						set rightpad	[expr {int(ceil($extra/2.0))}]
					}
					default {
						error "Unhandled alignment \"$align\""
					}
				}
				if {[tty printable_length $cell] > $colwidth} {
					set cell	[tty colour_clipped $cell $colwidth]
				}
				#set padded		[string repeat { } $leftpad]$cell[string repeat { } $rightpad]
				#if {[tty printable_length $padded] != $colwidth} {
				#	puts "align: $align, adjustment: $adjustment, colwidth: $colwidth, plen [tty printable_length $padded], padded: [regexp -all -inline .. [binary encode hex $padded]]"
				#}
				#set padded
				string cat \
					[string repeat { } $leftpad] \
					$cell \
					[string repeat { } $rightpad]
			}]]
			set row_length	[tty printable_length $row_txt]
			if {$row_length > [tty get columns]} {
				# Clip the row, while not counting the non-printing chars and resetting colour
				set row_txt	[tty colour_clipped $row_txt [tty get columns]]
			}
			append write_buf	$row_txt \n
			incr line
		}
		append write_buf	[colour $border_colour {string repeat = [tty get columns]}]

		set write_buf
	}

	#>>>
}

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
