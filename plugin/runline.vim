" Vim plugin to execute a line as Python code and insert the result.
" Last Change: 2010 Nov 5
" Maintainer:  Kevin Goodsell <kevin-opensource@omegacrash.net>
" License:     GPL (see below)

" {{{ COPYRIGHT & LICENSE
"
" Copyright 2010 Kevin Goodsell
"
" This program is free software: you can redistribute it and/or modify it under
" the terms of the GNU General Public License as published by the Free Software
" Foundation, either version 3 of the License, or (at your option) any later
" version.
"
" This program is distributed in the hope that it will be useful, but WITHOUT
" ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
" FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
" details.
"
" You should have received a copy of the GNU General Public License along with
" this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}
" {{{ DESCRIPTION
"
" This plugin provides just one command, RunLine, which takes no arguments.
" The RunLine command uses an external Python interpreter to evaluate the
" current line and write the results to the buffer, similar to how results are
" shown in the Python interactive interpreter. This is a quick way to run
" calculations without leaving Vim. There is no storage of variables between
" invocations of RunLine because each uses a new Python interpreter which
" exits upon completion.
"
" I recommend adding a mapping to execute RunLine quickly. For example, I have
" this in my .vimrc:
"
" nmap <Leader><CR> :RunLine<CR>
"
" }}}

if exists("loaded_runline")
    finish
endif
let loaded_runline = 1

if !executable("python")
    " No Python interpreter available.
    finish
endif

let s:save_cpo = &cpo
set cpo&vim

function! s:RunLine()
    " Get the line and remove leading white space.
    let line = matchstr(getline("."), '\v\s*\zs.*')

    " The line will be interpreted by Vim (in the exec command), the shell,
    " then as a python string. It has to be escaped and formatted for each of
    " these (in reverse order).

    " First, create the python string. Adds a backslash before existing
    " backslashes and single-quotes then puts the whole thing in single
    " quotes.
    let pystring = "'" . escape(line, "\\'") . "'"
    "echo pystring

    " Next, construct the shell command.
    let shellarg = "eval(compile(" . pystring . ", '<string>', 'single'))"
    let shellcmd = "python -c " . shellescape(shellarg)
    "echo shellcmd

    " Finally, construct the Vim command. '%' and '#' are escaped so they
    " don't get replaced with the current and alternate file names. '!' is
    " escaped so it doesn't get replaced with the previous :! command.
    let vimcmd = "silent read ! " . escape(shellcmd, "!%#")
    "echo vimcmd

    exec vimcmd
endfunction

if !exists(":RunLine")
    command -bar RunLine call s:RunLine()
endif

let &cpo = s:save_cpo

" {{{ TESTS
"
" Remove the first column before running tests. Each test is two lines, the
" line to execute and the expected output. Execute the line and compare the
" expected and actual results.
"
""abc123"
"'abc123'
"
"print " !#$%&'()*+,-./:;<=>?@[]^_`{|}~"
" !#$%&'()*+,-./:;<=>?@[]^_`{|}~
"
"print '\\\''
"\'
"
"print "\\\""
"\"
"
"2 ** 64
"18446744073709551616L
"
"0x10000000000000000
"18446744073709551616L
"
" }}}
