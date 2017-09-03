" Vim global plugin for highlighting questionable spacing and long lines
" Last Change: 2017 Sept 3
" Maintainer:  Kevin Goodsell <kevin-opensource@omegacrash.net>
" License:     GPL (see below)

" {{{ COPYRIGHT & LICENSE
"
" Copyright 2010-2017 Kevin Goodsell
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
" This plugin highlights some common formatting problems. Warnings for
" different types of problems can be selectively enabled and disabled. The
" specific warnings that are available are:
"
" inner-tab
"   Tab characters used anywhere other than the beginning of a line (but not
"   those picked up by the mixed-indent warning). This tends to produce
"   tab-stop-dependent formatting, so it won't look right for people using
"   different tab-stops.
"
" long-line
"   Lines longer than 80 columns (the exact number is configurable).
"   Characters beyond the limit are highlighted. This uses Vim's "virtual
"   columns", not the number or actual characters.
"
" mixed-indent
"   Indents that consist of both tabs and spaces. However, this make an
"   exception for lines that begin with tabs followed by spaces since it's
"   common to use tabs up to the current indentation level, then spaces to
"   align text. Only a tab-and-space sequence at the beginning of a line, with
"   tabs following spaces, is detected.
"
" trailing-space
"   Any whitespace at the end of a line.
"
" User Commands:
"
" FmtWarnOn [warning-name ...]
"   Turns on the given warnings for this buffer, and also toggles warnings on
"   for this buffer. Any number of warning names, or 'all', may be given. With
"   no warning names, just toggles warnings on without changing specific
"   warning enabled states. Tab-completion is supported.
"
" FmtWarnOff warning-name [warning-name ...]
"   Turns off the given warnings for this buffer. Does not change the toggle
"   state. At least one warning must be given, but more may be given. 'all' is
"   also accepted. Tab-completion is supported.
"
" FmtWarnToggle
"   Change the toggle state for this buffer, displaying or hiding warnings
"   without changing the enable state of the warnings. This allows hiding
"   warnings without forgetting which warnings were in use, and restoring
"   them later.
"
" FmtWarnLineLength [length]
"   Set the line length for this buffer. Characters beyond this point in the
"   line will be highlighted. Without an argument the current length is printed.
"   This can be used in a FileType autocmd if you use different line lengths
"   with different file types. The 'textwidth' setting is not affected by this,
"   but it might be a good idea to set it to the same value.
"
" Configuration:
"
" Configuration options are available as variables and as highlight groups:
"
" g:fmtwarn_default_line_length
"   This is the default line length after which the long-line warning kicks in.
"   Default is 80.
"
" g:fmtwarn_default_toggle
"   The initial toggle state for new buffers. Should be 0 or 1, to disable or
"   enable warnings initially.
"
" g:fmtwarn_include_warnings
"   The initially enabled warnings for new buffers. This is a list of warning
"   names as strings. Default is all warnings.
"
" g:fmtwarn_match_priority
"   This is the priority assigned to the match groups used to highlight
"   warning-provoking text. See :h matchadd() for a description of what this
"   means. The default is -1 to make it have a lower priority than hlsearch
"   highlighting.
"
" g:fmtwarn_exclude_filetypes
"   This is a list of filetypes for which the initial toggle state should
"   always be off. Defaults to ['help', 'qf'] to avoid showing warnings in
"   Vim's help and quickfix windows.
"
" fmtwarnWarning
"   This is the default highlight group for warnings. You can set the
"   highlighting for all warning types by setting this with :hi. It is linked
"   to Error by default.
"
" fmtwarnTrailingSpace, fmtwarnMixedIndent, fmtwarnInnerTab, fmtwarnLongLine
"   Highlight groups for specific warnings. You can use different highlighting
"   for specific warnings by setting these with :hi. They all link to
"   fmtwarnWarning by default.
"
" }}}
" {{{ OPERATION
"
" We use matches (see :h :match) to highlight warnings. This is because
" syntax-based matches don't necessarily play nice with the language syntax
" scripts.
"
" Matches are per-window, but we want warnings to be per-buffer. To accomplish
" this, we store a buffer variable (b:fmtwarn) in each buffer and a window
" variable (w:fmtwarn_matches) in each window. b:fmtwarn stores the intended
" warning state (whether warnings are currently displayed or not, and which
" warnings are enabled for the buffer). When a window is created or has its
" buffer changed, we update it using the information in b:fmtwarn. This update
" includes turning warning matches on or off as needed.
"
" Turning matches off is simply a matter of removing it from the set of window
" matches (using matchdelete()). Turning matches on requires either creating a
" new match or somehow restoring a previously deleted match. Rather than wasting
" match IDs by always creating new ones, we really want to restore the old
" match. This is accomplished by storing all the match information in
" w:fmtwarn_matches.
"
" Newly created buffers are set up by an autocmd on the BufWinEnter event. Newly
" created windows are likewise set up by an autocmd on the WinEnter event.
"
" }}}

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

if !exists("g:fmtwarn_default_line_length")
    let g:fmtwarn_default_line_length = 80
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

if !exists("g:fmtwarn_exclude_filetypes")
    let g:fmtwarn_exclude_filetypes = ["help", "qf"]
endif

" }}}
" {{{ INTERNALS

" Highlight groups
highlight default link fmtwarnWarning Error
highlight default link fmtwarnTrailingSpace fmtwarnWarning
highlight default link fmtwarnMixedIndent fmtwarnWarning
highlight default link fmtwarnInnerTab fmtwarnWarning
highlight default link fmtwarnLongLine fmtwarnWarning

function! s:FmtWarnWarning(msg)
    echohl WarningMsg
    try
        redraw
        echo a:msg
    finally
        echohl NONE
    endtry
endfunction

" This is the central place to determine if a buffer should not have this plugin
" active at all. The command line window, for example, doesn't work at all.
function! s:FmtWarnExcludeBuffer()
    " Hard to say what would be a reliable way to identify the command line
    " window.
    let is_command_line_window = &buftype ==# "nofile" && &statusline == ""

    return is_command_line_window
endfunction

function! s:FmtWarnExcludeBufferWithWarning()
    if s:FmtWarnExcludeBuffer()
        call s:FmtWarnWarning("FmtWarn not supported in this buffer.")
        return 1
    endif

    return 0
endfunction

" Create the buffer variable b:fmtwarn if it doesn't already exist.
function! s:FmtWarnInitBuffer()
    if !exists("b:fmtwarn")
        let b:fmtwarn = {}
        let b:fmtwarn.toggle = g:fmtwarn_default_toggle
        let b:fmtwarn.line_length = g:fmtwarn_default_line_length
        let b:fmtwarn.enabled = copy(g:fmtwarn_include_warnings)
    endif
endfunction

function! s:FmtWarnGetMatch(group_name)
    for m in getmatches()
        if m.group ==# a:group_name
            return m
        endif
    endfor

    return {}
endfunction

" Add a match if it doesn't exist, or replace it if it does exist. Matches are
" identified by the group name. In addition to setting match for this window,
" also updates w:fmtwarn_matches.
function! s:FmtWarnAddOrUpdateMatch(group, pattern)
    let match = s:FmtWarnGetMatch(a:group)
    if empty(match)
        " No such match has been created. Do it now.
        call matchadd(a:group, a:pattern, g:fmtwarn_match_priority)
    else
        " The match exists, so we will update it while maintaining the id. That
        " means deleting then adding with the new pattern, but the old match id.
        call matchdelete(match.id)
        call matchadd(a:group, a:pattern, g:fmtwarn_match_priority, match.id)
    endif

    " Add it to the window matches, overwriting any old version.
    let w:fmtwarn_matches[a:group] = s:FmtWarnGetMatch(a:group)
endfunction

" Add or update the matches for the given window. Used to initially create the
" matches and to update the match patterns (which is required for changing the
" allowed line length).
function! s:FmtWarnRefreshWindowMatches()
    let w:fmtwarn_matches = {}

    " In the following patterns, spaces are paired with non-breaking spaces
    " (U+A0) so that the two types behave the same.

    " This pattern matches tabs that are NOT preceded by indentation
    " characters.
    call s:FmtWarnAddOrUpdateMatch("fmtwarnInnerTab", '\v(^[ \xA0\t]*)@<!\t+')
    call s:FmtWarnAddOrUpdateMatch("fmtwarnLongLine",
            \ printf('\v%%%dv.+', b:fmtwarn.line_length + 1))
    " This pattern matches any indentation (even none) followed by a
    " space-tab sequence, possibly followed by more indentation
    call s:FmtWarnAddOrUpdateMatch("fmtwarnMixedIndent",
            \ '\v^[ \xA0\t]*[ \xA0]\t[ \xA0\t]*')
    call s:FmtWarnAddOrUpdateMatch("fmtwarnTrailingSpace", '\v[ \xA0\t]+$')
endfunction

" Set the current window to win_num. Generally this can be easily done with exec
" win_num . "wincmd w", but this can rather stupidly give an E788 error in some
" cases. E.g., while running the FileType autocmd for a quickfix window opened
" with :copen, wincmd will give an error even if you are switching to the
" current window (that is, not switching at all).
"
" This function helps out by not switching unless the switch would actually have
" some effect. It seems likely the in general E788 will only happen on new
" buffers which are only displayed in the current window, so switching only when
" it's really necessary should be an effective work-around.
function! s:FmtWarnSetCurrentWindow(win_num)
    if winnr() != a:win_num
        exec a:win_num . "wincmd w"
    endif
endfunction

" Updates the display of the current buffer (in all windows it appears in) so
" that the visible warnings match settings in b:fmtwarn.
function! s:FmtWarnRefreshBuffer()
    if s:FmtWarnExcludeBuffer()
        return
    endif

    call s:FmtWarnInitBuffer()

    let bnum = bufnr("")
    let saved_win = winnr()
    try
        let last_win = winnr("$")
        for w in range(1, last_win)
            if winbufnr(w) == bnum
                call s:FmtWarnSetCurrentWindow(w)
                call s:FmtWarnRefreshWindow()
            endif
        endfor
    finally
        " Restore original window
        call s:FmtWarnSetCurrentWindow(saved_win)
    endtry
endfunction

" Updates the display of the current window so the visible warnings match
" settings in b:fmtwarn.
function! s:FmtWarnRefreshWindow()
    call s:FmtWarnRefreshWindowMatches()

    " Find all the warning highlight groups that should be included for
    " this window.
    let include_groups = {}
    if b:fmtwarn.toggle
        for warning in b:fmtwarn.enabled
            let hlgroup = s:hlgroups[warning]
            let include_groups[hlgroup] = 1
        endfor
    endif

    for m in getmatches()
        " Skip matches that aren't from this plugin.
        if m.group !~# '\v^fmtwarn'
            continue
        endif

        if has_key(include_groups, m.group)
            " This match is desired and already present, so leave it alone.
            unlet include_groups[m.group]
        else
            " This match is present but not desired, so delete it.
            call matchdelete(m.id)
        endif
    endfor

    " Anything left in include_groups is desired but not present, so add it.
    for group in keys(include_groups)
        let match = w:fmtwarn_matches[group]
        call matchadd(match.group, match.pattern, match.priority, match.id)
    endfor
endfunction

" Function invoked for FileType event.
function! s:FmtWarnFileType(ft)
    if s:FmtWarnExcludeBuffer()
        return
    endif

    " If this filetype is in the list of excluded filetypes, toggle warnings
    " off.
    if index(g:fmtwarn_exclude_filetypes, a:ft) >= 0
        " FileType can happen before the other events, so make sure b:fmtwarn
        " has been set up.
        call s:FmtWarnInitBuffer()
        let b:fmtwarn.toggle = 0
        call s:FmtWarnRefreshBuffer()
    endif
endfunction

" }}}
" {{{ AUTOCMDS

augroup FmtWarn
    autocmd!
    " BufWinEnter is invoked for newly opened buffers and newly displayed
    " buffers. WinEnter is invoked when a window is split, so the matches get
    " set in the newly created window.
    autocmd BufWinEnter,WinEnter * call s:FmtWarnRefreshBuffer()
    autocmd FileType * call s:FmtWarnFileType(expand("<amatch>"))
augroup END

" }}}
" {{{ USER COMMANDS

" Takes a list of warning names (or 'all'), sets them on for the current
" buffer. Changes toggle state to 'on'.
function! s:FmtWarnOn(...)
    if s:FmtWarnExcludeBufferWithWarning()
        return
    endif

    let new_warnings = s:FmtWarnArgs(a:000)

    for warning in b:fmtwarn.enabled
        let new_warnings[warning] = 1
    endfor

    let b:fmtwarn.enabled = keys(new_warnings)
    let b:fmtwarn.toggle = 1
    call s:FmtWarnRefreshBuffer()
    call s:FmtWarnReport()
endfunction

" Same as FmtWarnOn, but sets warnings off, and doesn't change toggle state.
function! s:FmtWarnOff(...)
    if s:FmtWarnExcludeBufferWithWarning()
        return
    endif

    let drop_warnings = s:FmtWarnArgs(a:000)
    let new_warnings = []
    for warning in b:fmtwarn.enabled
        if !has_key(drop_warnings, warning)
            call add(new_warnings, warning)
        endif
    endfor

    let b:fmtwarn.enabled = new_warnings
    call s:FmtWarnRefreshBuffer()
    call s:FmtWarnReport()
endfunction

function! s:FmtWarnToggle()
    if s:FmtWarnExcludeBufferWithWarning()
        return
    endif

    let b:fmtwarn.toggle = !b:fmtwarn.toggle
    call s:FmtWarnRefreshBuffer()
    call s:FmtWarnReport()
endfunction

" Implementation of the FmtWarnLineLength command. If the optional argument is
" given, it is the new length.
function! s:FmtWarnLineLength(...)
    if s:FmtWarnExcludeBufferWithWarning()
        return
    endif

    if a:0 == 0
        echo b:fmtwarn.line_length
    else
        if a:1 !~# '\v^\d+$'
            call s:FmtWarnWarning("Bad number format: " . a:1)
            return
        endif

        " Make sure the buffer variable exists.
        call s:FmtWarnInitBuffer()
        let b:fmtwarn.line_length = str2nr(a:1)
        call s:FmtWarnRefreshBuffer()
    endif
endfunction

function! s:FmtWarnArgs(args)
    let warnings = []
    for arg in a:args
        if arg ==# "all"
            let warnings = copy(s:warnings)
            break
        endif

        if !has_key(s:hlgroups, arg)
            echoerr "unknown warning: " . arg
            return {}
        endif
        call add(warnings, arg)
    endfor

    let result = {}
    for warning in warnings
        let result[warning] = 1
    endfor

    return result
endfunction

function! s:FmtWarnReport()
    if b:fmtwarn.toggle
        if len(b:fmtwarn.enabled) == 0
            echo "FmtWarn is on (but no warnings enabled)"
        else
            echo "FmtWarn is on (" . join(b:fmtwarn.enabled, " ") . ")"
        endif
    else
        echo "FmtWarn is off"
    endif
endfunction

function! s:FmtWarningCompletion(arglead, cmdline, cursorpos)
    return join(s:warnings + ["all"], "\n")
endfunction

command! -nargs=* -complete=custom,s:FmtWarningCompletion
    \ FmtWarnOn call s:FmtWarnOn(<f-args>)
command! -nargs=+ -complete=custom,s:FmtWarningCompletion
    \ FmtWarnOff call s:FmtWarnOff(<f-args>)
command! FmtWarnToggle call s:FmtWarnToggle()
command! -nargs=? FmtWarnLineLength call s:FmtWarnLineLength(<f-args>)

" }}}

let &cpo = s:save_cpo
