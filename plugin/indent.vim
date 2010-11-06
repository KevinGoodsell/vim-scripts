" Vim global plugin for detecting and setting indent style
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
" This plugin attempts to detect the indent style (tabs or some number of
" spaces) used in a file. It then sets options to be consistent with the
" detected style. This is useful if you often edit files with dissimilar
" indent styles.
"
" }}}
" {{{ NOTES
"
" Here I use 'spaces-n' to indicate n-space indents, and 'emacs-n-m' to
" indicate emacs-style mixed tabs & spaces with n-column indents and m-
" column tabs.
"
" This tries to detect the following indent styles:
" * tabs
" * spaces-2
" * spaces-4
" * spaces-8
" * emacs-2-4 (e.g., 2sp, tab, tab-2sp, 2tab)
" * emacs-2-8 (e.g., 2sp, 4sp, 6sp, tab, tab-2sp, tab-4sp...)
" * emacs-4-8 (e.g., 4sp, tab, tab-4sp, 2tab, 2tab-4sp)
"
" You can override the default commands used for each indent style by creating
" a g:indent_cmds dictionary with the style names as keys and the command to
" execute (in string form) as the values. See s:indent_cmds below as an example
" of how this is done. In g:indent_cmds you can supply only the indent styles
" you specifically want to override -- leave out the ones with satisfactory
" defaults.
"
" Usually this plugin will run automatically, but you can use some commands to
" run it manually:
"
" :IndentDetect
"     Runs the normal indent detection, just like what happens on file loading.
"
" :IndentSet <indent style>
"     Don't do any detection, just set the style indicated. This uses custom
"     indent commands from g:indent_cmds if it exists.
"
" If auto-detection isn't working right, you might get a hint about why by
" looking at the b:indent_debug variable.
"
" }}}

if exists("loaded_indent")
    finish
endif
let loaded_indent = 1

let s:save_cpo = &cpo
set cpo&vim

augroup IndentGuess
    autocmd!
    autocmd BufReadPost,StdinReadPost * IndentDetect
augroup END

if !exists(":IndentSet")
    command -nargs=1 -bar -complete=custom,s:GetCompletions
        \ IndentSet call s:IndentSet(<q-args>)
endif
if !exists(":IndentDetect")
    command -bar IndentDetect call s:IndentDetect()
endif

function! s:Debug(msg, ...)
    if empty(a:000)
        let formatted = a:msg
    else
        let formatted = call("printf", [a:msg] + a:000)
    endif
    if !exists("b:indent_debug")
        let b:indent_debug = formatted
    else
        let b:indent_debug .= "\n" . formatted
    endif
endfunction

" Note that :help 'ts' has some useful notes about this
let s:indent_cmds = {
    \ "tabs"      : "setl sw=8 sts=0 noet",
    \ "spaces-2"  : "setl sw=2 sts=2 et",
    \ "spaces-4"  : "setl sw=4 sts=4 et",
    \ "spaces-8"  : "setl sw=8 sts=8 et",
    \ "emacs-2-4" : "setl ts=4 sw=2 sts=2 noet",
    \ "emacs-2-8" : "setl ts=8 sw=2 sts=2 noet",
    \ "emacs-4-8" : "setl ts=8 sw=4 sts=4 noet",
\ }

let s:indent_patterns = {
    \ "tabs"      : '\v^\t+$',
    \ "spaces-2"  : '\v^(  )+$',
    \ "spaces-4"  : '\v^(    )+$',
    \ "spaces-8"  : '\v^(        )+$',
    \ "emacs-2-4" : '\v^\t*(  )?$',
    \ "emacs-2-8" : '\v^\t*(  ){,3}$',
    \ "emacs-4-8" : '\v^\t*(    )?$',
\ }

" This ordering is supposed to tell which style to prefer when the number
" of indents for multiple styles are approximately the same.
"
" Any valid spaces-8 indent is a valid spaces-4 indent, but the
" inverse is not true, so spaces-8 has to come first. Likewise
" for spaces-4 and spaces-2.
let s:ordering = [
    \ "spaces-8",
    \ "spaces-4",
    \ "spaces-2",
    \ "tabs",
    \ "emacs-2-4",
    \ "emacs-4-8",
    \ "emacs-2-8",
\ ]

function! s:GetCompletions(arglead, cmdline, cursorpos)
    return join(sort(copy(s:ordering)), "\n")
endfunction

" Compare based on the ordering above
function! s:StyleCompare(first, second)
    let i1 = index(s:ordering, a:first)
    let i2 = index(s:ordering, a:second)
    return i1 == i2 ? 0 : i1 > i2 ? 1 : -1
endfunction

function! s:PreprocessLines(lines)
    let lines = join(a:lines, "\n")
    " Remove C comments. Note that . matches newlines when searching a string.
    " Check :help string-match for more info
    let lines = substitute(lines, '\v/\*.{-}\*/', "", "g")

    let result = []
    " Remove lines that can't be used for indent guessing: empty, whitespace
    " only, tabs following spaces.
    for line in split(lines, "\n")
        if line !~ '\v(^[ \t]*$)|(^\t* +\t)' && line =~ '\v^[ \t]'
            call add(result, line)
        endif
    endfor

    return result
endfunction

function! s:IndentDetect()
    unlet! s:indent_debug

    " Up to 1000 lines are used for detection.
    let lines = s:PreprocessLines(getline(1, 1000))

    " Tally up the indent strings
    let indent_counts = {} " { 'indent' : num_occurrences }
    for line in lines
        let indent = matchstr(line, '\v^[ \t]+')
        let indent_counts[indent] = get(indent_counts, indent) + 1
    endfor

    let counts = map(items(indent_counts),
        \ "printf('%s: %d', tr(v:val[0], \" \t\", 'st'), v:val[1])")
    call s:Debug("indent counts: %s", string(counts))

    let style_counts = {} " { 'style' : num_occurrences }
    for [indent, cnt] in items(indent_counts)
        for [style, pattern] in items(s:indent_patterns)
            if indent =~ pattern
                let style_counts[style] = get(style_counts, style) + cnt
            endif
        endfor
    endfor

    if len(style_counts) == 0
        call s:Debug("No usable indents found.")
        return
    endif

    call s:Debug("line counts per style: %s", string(style_counts))

    let cutoff = max(style_counts) * 850 " 0.850
    let contenders = keys(filter(copy(style_counts),
                          \ "v:val * 1000 >= cutoff"))

    call s:Debug("contenders: %s", string(contenders))

    call sort(contenders, "s:StyleCompare")
    let style = contenders[0]

    call s:Debug("choosing " . style)

    call s:IndentSet(style)
endfunction

function! s:IndentSet(stylename)
    if exists("g:indent_cmds") && has_key(g:indent_cmds, a:stylename)
        let indent_cmd = g:indent_cmds[a:stylename]
    else
        if has_key(s:indent_cmds, a:stylename)
            let indent_cmd = s:indent_cmds[a:stylename]
        else
            echoerr "Invalid style name"
            return
        endif
    endif

    call s:Debug("Using command: %s", indent_cmd)

    exec indent_cmd
endfunction

let &cpo = s:save_cpo
