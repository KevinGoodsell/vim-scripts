" Vim global plugin for highlighting questionable spacing and long lines
" Last Change: XXX
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
" {{{ NOTES
"
" * Using :syntax would be simpler in some ways, but it's just not practical.
"   There's no way to make the priority higher than normal syntax, it's all
"   determined by the type of syntax item and the starting position.
"
" }}}

" XXX
" * Perhaps the match priority should be configurable.
" * Need a way to exclude files from default warnings.

if exists("loaded_fmtwarn")
    finish
endif
let loaded_fmtwarn = 1

let s:save_cpo = &cpo
set cpo&vim

" { 'warning-name' : 'highlightGroup'}
let s:warnings = {
    \ "inner-tab"      : "fmtwarnInnerTab",
    \ "long-line"      : "fmtwarnLongLine",
    \ "mixed-indent"   : "fmtwarnMixedIndent",
    \ "trailing-space" : "fmtwarnTrailingSpace",
\ }

" {{{ USER OPTIONS

if !exists("g:fmtwarn_line_length")
    let g:fmtwarn_line_length = 80
endif

if !exists("g:fmtwarn_default_toggle")
    let g:fmtwarn_default_toggle = 1
endif

if !exists("g:fmtwarn_include_warnings")
    let g:fmtwarn_include_warnings = keys(s:warnings)
endif

" }}}
" {{{ INTERNALS

" Highlight groups
highlight default link fmtwarnWarning Error
highlight default link fmtwarnTrailingSpace fmtwarnWarning
highlight default link fmtwarnMixedIndent fmtwarnWarning
highlight default link fmtwarnInnerTab fmtwarnWarning
highlight default link fmtwarnLongLine fmtwarnWarning

" Initialize format warnings for the current buffer
function! s:FmtWarnInit()
    if !exists("b:fmtwarn")
        let b:fmtwarn = {}
        let b:fmtwarn.toggle = g:fmtwarn_default_toggle
        let b:fmtwarn.warnings = map(copy(g:fmtwarn_include_warnings),
                                   \ "s:warnings[v:val]")
    endif
endfunction

" Reset warnings based on b:fmtwarn settings. Applies to all windows this
" buffer appears in.
function! s:FmtWarnSetBufferWarnings()
    let bnum = bufnr("")
    let last_win = winnr("$")
    for w in range(1, last_win)
        if winbufnr(w) == bnum
            call s:FmtWarnSetWindowWarnings(w)
        endif
    endfor
endfunction

" Reset warnings based on b:fmtwarn settings. Applies to the current window,
" or the window number given as the optional argument.
function! s:FmtWarnSetWindowWarnings(...)
    if a:0 == 1
        let saved_win = winnr()
        exec a:1 . "wincmd w"
    endif

    try
        " XXX Does this make sense?
        call s:FmtWarnInit()

        if !exists("w:fmtwarn_matches")
            call s:FmtWarnAddWindowMatches()
        endif

        " Find all the warning highlight groups that should be included for
        " this window.
        let include_groups = {}
        if b:fmtwarn.toggle
            for hlgroup in b:fmtwarn.warnings
                let include_groups[hlgroup] = 1
            endfor
        endif

        " Modify 'matches' to remove unwanted warnings and include wanted
        " warnings.
        let new_matches = []
        for m in getmatches()
            " Include matches from include_groups, as well as matches that
            " have nothing to do with this plugin.
            if m.group !~# '\v^fmtwarn' || has_key(include_groups, m.group)
                call add(new_matches, m)
                " Filter out already-included items.
                unlet! include_groups[m.group]
            endif
        endfor

        " Add anything left in include_groups
        for group in keys(include_groups)
            call add(new_matches, w:fmtwarn_matches[group])
        endfor

        call setmatches(new_matches)

    finally
        if exists("saved_win")
            exec saved_win . "wincmd w"
        endif
    endtry
endfunction

" Adds all the warning matches to a window.
function! s:FmtWarnAddWindowMatches()
    call matchadd("fmtwarnInnerTab", '\v(^[ \t]*)@<!\t+', -1)
    call matchadd("fmtwarnLongLine", '\v%80v.+', -1)
    call matchadd("fmtwarnMixedIndent", '\v^ +\t[ \t]*', -1)
    call matchadd("fmtwarnTrailingSpace", '\v\s+$', -1)

    let w:fmtwarn_matches = {}
    for m in getmatches()
        if m.group =~# '\v^fmtwarn'
            let w:fmtwarn_matches[m.group] = m
        endif
    endfor
endfunction

" }}}
" {{{ AUTOCMDS

augroup FmtWarn
    autocmd!
    autocmd BufWinEnter,WinEnter * call s:FmtWarnSetWindowWarnings()
augroup END

" }}}
" {{{ USER COMMANDS

function! s:FmtWarnOn(args)
    " XXX
endfunction

function! s:FmtWarnOff(args)
    " XXX
endfunction

function! s:FmtWarnToggle()
    if !exists("b:fmtwarn")
        echomsg "FmtWarn is not enabled for this buffer"
    endif
    let b:fmtwarn.toggle = !b:fmtwarn.toggle
    call s:FmtWarnSetBufferWarnings()
endfunction

command! -nargs=+ FmtWarnOn call s:FmtWarnOn(<f-args>)
command! -nargs=+ FmtWarnOff call s:FmtWarnOff(<f-args>)
command! FmtWarnToggle call s:FmtWarnToggle()

" }}}

let &cpo = s:save_cpo
