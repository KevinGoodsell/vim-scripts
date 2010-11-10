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
" * Need a way to exclude files from default warnings.

if !exists("*matchadd")
    " This Vim doesn't have the necessary features.
    finish
endif

if exists("loaded_fmtwarn")
    finish
endif
let loaded_fmtwarn = 1

let s:save_cpo = &cpo
set cpo&vim

" { 'warning-name' : 'highlightGroup'}
let s:hlgroups = {
    \ "inner-tab"      : "fmtwarnInnerTab",
    \ "long-line"      : "fmtwarnLongLine",
    \ "mixed-indent"   : "fmtwarnMixedIndent",
    \ "trailing-space" : "fmtwarnTrailingSpace",
\ }

let s:warnings = sort(keys(s:hlgroups))

" {{{ USER OPTIONS

if !exists("g:fmtwarn_line_length")
    let g:fmtwarn_line_length = 80
endif

if !exists("g:fmtwarn_default_toggle")
    let g:fmtwarn_default_toggle = 1
endif

if !exists("g:fmtwarn_include_warnings")
    let g:fmtwarn_include_warnings = s:warnings
endif

if !exists("g:fmtwarn_match_priority")
    " -1 is lower than hlsearch.
    let g:fmtwarn_match_priority = -1
endif

" }}}
" {{{ INTERNALS

" Highlight groups
highlight default link fmtwarnWarning Error
highlight default link fmtwarnTrailingSpace fmtwarnWarning
highlight default link fmtwarnMixedIndent fmtwarnWarning
highlight default link fmtwarnInnerTab fmtwarnWarning
highlight default link fmtwarnLongLine fmtwarnWarning

" Initialize format warnings for the current buffer and window.
function! s:FmtWarnInit()
    if !exists("b:fmtwarn")
        let b:fmtwarn = {}
        let b:fmtwarn.toggle = g:fmtwarn_default_toggle
        let b:fmtwarn.enabled = map(copy(g:fmtwarn_include_warnings),
                                  \ "s:hlgroups[v:val]")
    endif

    if !exists("w:fmtwarn_matches")
        call s:FmtWarnAddWindowMatches()
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
        " Set up buffer and window vars if not already done.
        call s:FmtWarnInit()

        " Find all the warning highlight groups that should be included for
        " this window.
        let include_groups = {}
        if b:fmtwarn.toggle
            for hlgroup in b:fmtwarn.enabled
                let include_groups[hlgroup] = 1
            endfor
        endif

        " Modify 'matches' to remove unwanted warnings and include wanted
        " warnings.
        let new_matches = []
        for m in getmatches()
            " Include matches from include_groups, as well as matches that
            " have nothing to do with this plugin.
            " Include matches that aren't from this plugin.
            if m.group !~# '\v^fmtwarn'
                call add(new_matches, m)
            " Include matches from include_groups, and remove them so they
            " don't get double-added.
            elseif has_key(include_groups, m.group)
                call add(new_matches, m)
                unlet include_groups[m.group]
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
    let priority = g:fmtwarn_match_priority
    call matchadd("fmtwarnInnerTab", '\v(^[ \t]*)@<!\t+', priority)
    call matchadd("fmtwarnLongLine", '\v%80v.+', priority)
    call matchadd("fmtwarnMixedIndent", '\v^ +\t[ \t]*', priority)
    call matchadd("fmtwarnTrailingSpace", '\v\s+$', priority)

    let w:fmtwarn_matches = {}
    for m in getmatches()
        if m.group =~# '\v^fmtwarn'
            let w:fmtwarn_matches[m.group] = m
        endif
    endfor
endfunction

function! s:FmtWarnCheck()
    if exists("b:fmtwarn")
        return 1
    endif

    echomsg "FmtWarn is not enabled for this buffer"
    return 0
endfunction

" }}}
" {{{ AUTOCMDS

augroup FmtWarn
    autocmd!
    autocmd BufWinEnter,WinEnter * call s:FmtWarnSetWindowWarnings()
augroup END

" }}}
" {{{ USER COMMANDS

" Takes a list of warning names (or 'all'), sets them on for the current
" buffer. Changes toggle state to 'on'.
function! s:FmtWarnOn(...)
    if !s:FmtWarnCheck()
        return
    endif

    let new_groups = s:FmtWarnArgsToGroups(a:000)

    for group in b:fmtwarn.enabled
        let new_groups[group] = 1
    endfor

    let b:fmtwarn.enabled = keys(new_groups)
    let b:fmtwarn.toggle = 1
    call s:FmtWarnSetBufferWarnings()
endfunction

" Same as FmtWarnOn, but sets warnings off, and doesn't change toggle state.
function! s:FmtWarnOff(...)
    if !s:FmtWarnCheck()
        return
    endif

    let drop_groups = s:FmtWarnArgsToGroups(a:000)
    let new_groups = []
    for group in b:fmtwarn.enabled
        if !has_key(drop_groups, group)
            call add(new_groups, group)
        endif
    endfor

    let b:fmtwarn.enabled = new_groups
    call s:FmtWarnSetBufferWarnings()
endfunction

function! s:FmtWarnToggle()
    if !s:FmtWarnCheck()
        return
    endif
    let b:fmtwarn.toggle = !b:fmtwarn.toggle
    call s:FmtWarnSetBufferWarnings()
endfunction

function! s:FmtWarnArgsToGroups(args)
    let groups = []
    for arg in a:args
        if arg == "all"
            let groups = values(s:hlgroups)
            break
        endif

        let group = get(s:hlgroups, arg, "")
        if len(group) == 0
            echoerr "unknown warning: " . arg
            return {}
        endif
        call add(groups, group)
    endfor

    let result = {}
    for group in groups
        let result[group] = 1
    endfor

    return result
endfunction

function! s:FmtWarningCompletion(arglead, cmdline, cursorpos)
    return join(s:warnings + ["all"], "\n")
endfunction

command! -nargs=* -complete=custom,s:FmtWarningCompletion
    \ FmtWarnOn call s:FmtWarnOn(<f-args>)
command! -nargs=+ -complete=custom,s:FmtWarningCompletion
    \ FmtWarnOff call s:FmtWarnOff(<f-args>)
command! FmtWarnToggle call s:FmtWarnToggle()

" }}}

let &cpo = s:save_cpo
