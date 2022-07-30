% tty(n) 1.0 | TTY and ANSI control for Tcl
% Cyan Ogilvie
% 0.1

# NAME

tty - Control TTY terminals and ANSI colour sequences

# SYNOPSIS

**package require tty** ?0.1?

**tty strip_ansi** *string*

**tty printable_length** *string*

**tty c** ?colour ...?

**tty colour** ?colour ...? *script*

**tty colour_format** *formatString* ?arg ...?

**tty table** ?options?

**tty setup**

**tty get columns**

**tty get lines**

**tty set_mode_cursor**

**tty reset_mode_cursor**

**tty clear**

**tty clear_to_end**

**tty goto** *line* *column*

**tty set_scroll_region** *from* *to*

**tty clear_to_end_of_line**

**tty goto_last_line**

**tty on_resize** *key* *cb*

**tty save_cursor** *script*

**tty can** *capability*

**tty init**

**tty reset**

# DESCRIPTION

This package allows Tcl scripts to control TTYs (move cursors, set scroll
regions, clear portions of the screen, etc), and work with ANSI colour
escape sequences, and provides some utility functions built upon these.

There is a lot of overlap between the scope of this package and the term::\*
packages in tcllib.  Consider using the tcllib implementation if your platform
can't exec tput, or you lack one of the required packages (tclsignal, parse_args).

# COMMANDS

**tty strip_ansi** *string*
:   Return *string* with all ANSI escape sequences and characters between
    SOH (\x01) and SOT (\x02) removed.

**tty printable_length** *string*
:   Return the number of printable characters in *string* - that is - the
    number of columns it occupies on the terminal.

**tty c** ?colour ...?
:   Output an ANSI escape sequence that changes the text colour to the
    set specified.  See **COLOUR CODES** below.

**tty colour** ?colour ...? *script*
:   Execute *script* and return its result, wrapped in ANSI escape sequences to
    colourise the returned result with each of the supplied colours, and resetting
    the colour afterwards.

**tty colour_format** *formatString* ?arg ...?
:   Wrapper around **format** which adjusts the string field widths to
    compensate for ANSI escape sequences (non-printing characters).

**tty table** ?options?
:   Format the input data into a tabular output and return the formatted
    text.  Options:

    | Option | Required | Description |
    |---|---|---|
    | -data | required | The input data to format, as a list of dictionaries |
    | -columns | required | Definition of the output columns.  See **TABLE COLUMN FORMAT** for details |
    | -col_sep | no, default: " \| " | The characters to use to separate adjacent table cells horizontally |
    | -formatters | no, default {} | A dictionary, keyed by the column name, whose values are lambdas that take the raw column value and return a transformed version to display |
    | -border_colour | no, default white | The colour to use when displaying table separators or structure |

**tty setup**
:   Register a signal handler to respond to SIGWINCH correctly, initialize the terminal,
    set cursor mode and hook ::exit for required cleanup.

**tty get columns**
:   Return the current width of the terminal in characters.  Value is cached and
    automatically updated on SIGWINCH.

**tty get lines**
:   Return the current height of the terminal in lines.  Value is cached ands
     automatically updated on SIGWINCH.

**tty set_mode_cursor**
:   Set cursor mode.  Configures the terminal for applications that use cursor movement.

**tty reset_mode_cursor**
:   Resets the terminal from cursor mode.

**tty clear**
:   Clear the screen

**tty clear_to_end**
:   Erases the content in the terminal from the current cursor position to the end
    of the terminal window.

**tty goto** *line* *column*
:   Move the cursor to the specified *line* and *column*.  Both *line* and *column* are
    0-based, ie. position 0, 0 is the top-left character cell in the terminal window.

**tty set_scroll_region** *from* *to*
:   Set the range of lines that will scroll, from *from* to *to*, inclusive.

**tty clear_to_end_of_line**
:   Erases content from the current cursor position to the end of the line.

**tty goto_last_line**
:   Move the cursor to the start of the last line of the terminal window.

**tty on_resize** *key* *cb*
:   Register a callback to be invoked when the terminal window resizes.  *key* is
    some unique name for this callback, and *cb* is a script to run when the
    terminal is resized.  The values of [tty get columns] and [tty get lines]
    will reflect the new size in the callback.  To remove the callback, pass
    the *key* used to register it, with an empty *cb*.

**tty save_cursor** *script*
:   Execute *script* (in the caller's frame), saving the cursor position before
    and restoring it after executing *script*.  DOES NOT NEST.

**tty can** *capability*
:   Return a boolean value indicating whether the current terminal supports
    *capability*.  Available capabilities that can be tested are:

    | capability | Description |
    |---|---|
    | overstrike | Does this terminal support overstrike? |
    | statusline | Does this terminal have a status line? |

**tty init**
:   Send the init sequences defined for this terminal.

**tty reset**
:   Send the reset sequences defined for this terminal.

# COLOUR CODES

| Code | Description |
|---|---|
| black | Foreground black |
| red | Foreground red |
| green | Foreground green |
| yellow | Foreground yellow |
| blue | Foreground blue |
| purple | Foreground purple |
| cyan | Foreground cyan |
| white | Foreground white |
| bg_black | Background black |
| bg_red | Background red |
| bg_green | Background green |
| bg_yellow | Background yellow |
| bg_blue | Background blue |
| bg_purple | Background purple |
| bg_cyan | Background cyan |
| bg_white | Background white |
| inverse | Invert background and foreground |
| bold | Text to bold |
| underline | Underline text |
| bright | Foreground bright |
| norm | Reset foreground and background to default |
| bg_#rrggbb | Set background to the HTML-style 24bit hexadecimal colour rrggbb |
| fg_#rrggbb | Set foreground to the HTML-style 24bit hexadecimal colour rrggbb |

# TABLE COLUMN FORMAT

The **tty table** command takes a list of columns, each of which is a list of 4 elements:

- The column title.
- The column key (key into the row dictionary for this column's value).
- The alignment of the characters within this column, one of: *left*, *right*, *centre*.
- Additional options for this column's format.  Currently supported is *-size*, which can take the values *fixed*, *grow*, *shrink* or *both*, and which controls how this column's width is adjusted in response to an excess or deficit in the availability of space for the table.

# EXAMPLES

Format a table:

```tcl
set data {
    {
        server      web1
        status      up
        r/s         23.4163626
    }
    {
        server      web2
        status      down
        r/s         {}
    }
    {
        server      web3
        status      up
        r/s         21.4381318
    }
}

puts [tty table \
    -data $data \
    -columns {
        { Status       status  centre  {-size fixed} }
        { Server       server  left    {-size grow}  }
        { Requests/sec r/s     right   {-size fixed} }
    } -formatters {
        status {v {
            if {$v eq "up"} {
                tty colour green {set v}
            } else {
                tty colour red {set v}
            }
        }}
        r/s {v {
            if {$v eq ""} {
                tty colour red {return -level 0 --}
            } else {
                format %.1f $v
            }
        }}
    } \
]
```

# LICENSE

This package is Copyright 2021 Cyan Ogilvie, and is made available under
the same license terms as the Tcl Core.

