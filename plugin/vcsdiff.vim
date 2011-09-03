" Vim global plugin to diff a buffer against an earlier version in a VCS.
" Last Change: 2011 September 3
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
" {{{ COMMANDS
"
" VcsDiffList
"   List available version control systems and commands for each.
"
" VcsDiffHelp [commands]
"   Show help for the commands given, or all available commands if none are
"   given.
"
" }}}
" {{{ OPTIONS
"
" g:vcsdiff_include
"   A list of version control system names. If defined, only commands for the
"   given systems will be available. Leaving undefined makes all commands
"   available.
"
" g:vcsdiff_new_win_prefix
"   This is a Vim command that will be used as a prefix for the 'new' command
"   when creating a new window. Used to determine where new windows appear.
"   This could be 'vertical', 'leftabove', 'rightbelow', 'topleft',
"   'bottomright', or any reasonable combination. Default is 'vertical'.
"
" g:vcsdiff_cursor_new_window
"   Evaluated as a boolean. If true, when a new window is opened the cursor
"   will be placed in the new window. If false, the cursor will remain in the
"   current window. Default is true.
"
" g:vcsdiff_statusline
"   Value used for 'statusline' in diff buffers. It's good to keep this sparse
"   so there's room for extra info about the revision, etc. The filename (%f)
"   should always be included, since that's where the extra info actually
"   comes from.
"
" }}}
" {{{ NOTES
"
" Known Bugs:
" * If you close the original buffer then open it again (with the diff buffer
"   still around), it will still be in diff mode. However, scrollbind
"   typically gets turned off in this case. This is normal scrollbind
"   behavior, see :h 'scrollbind'.
"
" }}}
" {{{ DEFINITIONS

if exists("loaded_vcsdiff")
    finish
endif
let loaded_vcsdiff = 1

let s:save_cpo = &cpo
set cpo&vim

let s:vcs_names = []
let s:command_names = {} " {'vcsname' : ['DiffCommandName']}
let s:command_help = {} " {'DiffCommandName' : 'help string'}

if exists("g:vcsdiff_include")
    let s:include = g:vcsdiff_include
else
    let s:include = s:vcs_names
endif

if !exists("g:vcsdiff_new_win_prefix")
    let g:vcsdiff_new_win_prefix = "vertical"
endif

if !exists("g:vcsdiff_cursor_new_window")
    let g:vcsdiff_cursor_new_window = 1
endif

if !exists("g:vcsdiff_statusline")
    " This is designed to leave as much room as possible, and truncate on the
    " right if necessary.
    let g:vcsdiff_statusline = "%f%<"
endif

" }}}
" {{{ UTILITY FUNCTIONS

" s:Strip(str) returns a copy of str with leading and trailing whitespace
" removed.
function! s:Strip(str)
    return substitute(a:str, '\v^[ \t\r\n]*(.{-})[ \t\r\n]*$', '\1', "")
endfunction

" s:RunCmd() is a helper for functions that run a shell command. Don't call it
" directly.
function! s:RunCmd(cmd, write_output)
    let stderr_temp = tempname()
    let saved_shellredir = &shellredir
    try
        let &shellredir = ">%s 2>" . stderr_temp

        if a:write_output
            exec "read ! " . a:cmd
            let result = ""
        else
            let result = system(a:cmd)
        endif

        let s:shell_stderr = s:Strip(join(readfile(stderr_temp), "\n"))

        if v:shell_error != 0
            if len(s:shell_stderr) > 0 && len(s:shell_stderr) < 200
                let msg = s:shell_stderr
            else
                let msg = printf("command execution failed (error code %d)",
                               \ v:shell_error)
            endif
            throw msg
        endif
    finally
        call delete(stderr_temp)
        let &shellredir = saved_shellredir
    endtry

    return result
endfunction

" s:WriteCmdOutput(cmd) executes a command and writes the output to the
" current buffer without an extra empty line and without trashing registers.
" This currently assumes the buffer is initially empty.
function! s:WriteCmdOutput(cmd)
    call s:RunCmd(a:cmd, 1)
    " RunCmd (using :read!) inserts below the cursor, leaving an empty line in
    " a previously empty buffer. Delete the line without saving it in a
    " register.
    1 delete _
endfunction

" s:GetCmdOutput works like system(), but only returns stdout and throws on
" error. stderr can be retrieved from s:shell_stderr.
function! s:GetCmdOutput(cmd)
    return s:RunCmd(a:cmd, 0)
endfunction

" Vim has no rethrow.
function! s:Rethrow()
    let except = v:exception

    " Add source info if it's not already there.
    if except !~# '\v \[from .*\]$'
        let except = printf("%s [from %s]", except, v:throwpoint)
    endif

    " Can't directly throw Vim exceptions (see :h try-echoerr), so use echoerr
    " instead, but strip off an existing echoerr prefix first.
    if except =~# '\v^Vim'
        echoerr substitute(except, '\v^Vim\(echoerr\):', "", "")
    endif

    throw except
endfunction

" Set the name for the buffer.
function! s:SetBufName(name)
    exec "silent file " . fnameescape(a:name)
endfunction

" Helper for s:Wrap. Don't call directly.
function! s:BuildLine(words, width, prefix)
    let line = [a:words[0]]
    let size = len(a:prefix) + len(a:words[0])
    for word in a:words[1:]
        let newsize = size + 1 + len(word)
        if newsize > a:width
            break
        endif
        call add(line, word)
        let size = newsize
    endfor

    call remove(a:words, 0, len(line) - 1)
    let linestr = a:prefix . join(line, " ")

    " A line made of a single long word can be too long. Break the word and
    " put the remainder back in a:words.
    if len(linestr) > a:width
        " 'a:width:' looks like a variable name, so add a space before ':'
        call insert(a:words, linestr[a:width :])
        let linestr = linestr[:a:width - 1]
    endif
    return linestr
endfunction

" Wrap a string to the given width, indenting lines after the first.
function! s:Wrap(str, width)
    if a:width <= 2
        throw printf("can't wrap to such a narrow width (%d chars)", a:width)
    endif

    let words = split(a:str, '\v[ \t\n]+')
    let lines = []

    call add(lines, s:BuildLine(words, a:width, ""))

    while !empty(words)
        call add(lines, s:BuildLine(words, a:width, "  "))
    endwhile

    return join(lines, "\n")
endfunction

" Show an error message with ErrorMsg highlighting, also saving in :messages.
" It may be necessary to :redraw first if the screen is being updated.
function! s:ErrorMsg(msg)
    echohl ErrorMsg
    echomsg a:msg
    echohl None
endfunction

" }}}
" {{{ INNER WORKINGS

function! s:AddVcsDiff(vcs_name, cmd_name, buffer_func, nargs, help)
    call add(s:vcs_names, a:vcs_name)
    let cmds = get(s:command_names, a:vcs_name, [])
    let s:command_names[a:vcs_name] = add(cmds, a:cmd_name)
    if index(s:include, a:vcs_name) != -1
        let s:command_help[a:cmd_name] = a:help
        " 2 is for an exact match
        if exists(":" . a:cmd_name) != 2
            exec printf("command -nargs=%s %s call s:Diff('%s', [<f-args>])",
                      \ a:nargs, a:cmd_name, a:buffer_func)
        endif
    endif
endfunction

function! s:Diff(funcname, args)
    if s:HasDiffBuffer()
        call s:ErrorMsg("diff already active")
        return
    elseif expand("%") == ""
        call s:ErrorMsg("no file to diff")
        return
    endif

    let saveddir = getcwd()
    " Error handling is tricky, but just being in a try block makes vim throw
    " errors instead of reporting and continuing. See :help except-compat.
    try
        " Gather info
        let filetype = &filetype
        " Save command to restore everything to the pre-diff state. These are
        " mostly window settings, but we save in a buffer variable. The reason
        " is that we can't rely on window variables. From :h local-options:
        "
        "   When editing a buffer that has been edited before, the last used
        "   window options are used again.  If this buffer has been edited in
        "   this window, the values from back then are used.  Otherwise the
        "   values from the window where the buffer was edited last are used.
        "
        " Therefore if the buffer is hidden while in diff mode and later
        " re-displayed, the old window settings come back. This is also the
        " reason for the autocmd that follows.
        let b:vcsdiff_restore = "diffoff|"
            \ . "setlocal"
            \ . (&diff ? " diff" : " nodiff")
            \ . (&scrollbind ? " scrollbind" : " noscrollbind")
            \ . " scrollopt=" . &scrollopt
            \ . (&wrap ? " wrap" : " nowrap")
            \ . " foldmethod=" . &foldmethod
            \ . " foldcolumn=" . &foldcolumn
        " Make sure we can restore things even if the buffer has been hidden.
        autocmd BufWinEnter <buffer>
            \ exec "if !s:HasDiffBuffer()|call s:Undiff()|endif"

        " Most systems will require being in the directory of the file, or at
        " least in the repository working dir.
        exec "cd " . fnameescape(expand("%:h"))
        let fname = expand("%:t")

        " Prepare starting buffer
        diffthis

        " Create and prepare new buffer.
        exec g:vcsdiff_new_win_prefix . " new"
        try
            " See :help special-buffers. For bufhidden, only hide or wipe seem
            " to make any sense. Otherwise the buffer is unloaded and anything
            " that's left isn't useful.
            setlocal buftype=nofile bufhidden=wipe
            let &l:statusline = g:vcsdiff_statusline
            call call(a:funcname, [fname, a:args])
            setlocal nomodifiable
            let &l:filetype = filetype
            diffthis
            let b:vcsdiff_diffbuffer = 1
            autocmd BufWinLeave <buffer> call s:Undiff()
        catch
            " Close the new window, then propagate the error so it can be
            " reported.
            close
            call s:Rethrow()
        endtry

        if !g:vcsdiff_cursor_new_window
            wincmd p
        endif

    catch
        " Undo any changes made to the original buffer and window, then report
        " the error.
        call s:Undiff()
        " Error messages may be hidden when the redraw occurs, so force it
        " now.
        redraw
        call s:ErrorMsg(v:exception)

    finally
        " Clean up
        exec "cd " . fnameescape(saveddir)
    endtry
endfunction

function! s:HasDiffBuffer()
    let last_buf = bufnr("$")
    for i in range(1, last_buf)
        if getbufvar(i, "vcsdiff_diffbuffer")
            return 1
        endif
    endfor
endfunction

function! s:Undiff()
    let cur_win = winnr()
    let last_win = winnr("$")
    " Loop through all windows executing restore commands where they exist.
    " The actual diff buffer could be in 0 or more windows. In the 0 case,
    " nothing happens, but there's an autocmd to fix up the buffer next time
    " it is displayed. In the 1 window case, the window settings are restored.
    " If the buffer is in several windows, we restore all of them.
    for i in range(1, last_win)
        exec i . "wincmd w"
        if exists("b:vcsdiff_restore")
            exec b:vcsdiff_restore
        endif
    endfor
    " Repeat the loop, this time to remove the stuff attached to the buffer.
    " Doing this after visiting all of the windows makes sure that all windows
    " displaying the diff buffer get restored.
    for i in range(1, last_win)
        exec i . "wincmd w"
        if exists("b:vcsdiff_restore")
            unlet b:vcsdiff_restore
            autocmd! BufWinLeave <buffer>
        endif
    endfor
    exec cur_win . "wincmd w"
endfunction

function! s:List()
    echo "Supported Version Control Systems (* = currently enabled)"
    for [name, cmds] in items(s:command_names)
        if index(s:include, name) != -1
            let used = "*"
        else
            let used = " "
        endif
        echo printf("%s %s (%s)", used, name, join(cmds, ", "))
    endfor
endfunction

function! s:Help(...)
    if empty(a:000)
        let cmds = sort(keys(s:command_help))
    else
        let cmds = a:000
    endif
    for cmd in cmds
        let help = get(s:command_help, cmd, "")
        if help == ""
            call s:ErrorMsg("no help for " . cmd)
        else
            " Use &columns - 1 because going the full screen width auto-wraps,
            " leaving blank lines.
            echo s:Wrap(help, &columns - 1)
        endif
    endfor
endfunction

function! s:HelpCompletion(arg_lead, cmd_line, cursor_pos)
    let cmds = sort(keys(s:command_help))
    return join(cmds, "\n")
endfunction

if !exists(":VcsDiffList")
    command! VcsDiffList call s:List()
endif
if !exists(":VcsDiffHelp")
    command! -nargs=* -complete=custom,s:HelpCompletion
        \ VcsDiffHelp call s:Help(<f-args>)
endif

" }}}
" {{{ VCS FUNCTIONS

let s:rev_info_failed_msg = "[failed to get rev info]"

function! s:GitUnmodified(fname, args)
    if empty(a:args)
        " Diffing against index version, but if the index version is the same as
        " HEAD then follow it back to where this version was actually committed.
        " This gives more useful information in the status line.
        call system("git diff-index --cached --quiet HEAD " . a:fname)
        if v:shell_error
            let commit = ""
        else
            let base_rev = "HEAD"
        endif
    else
        let base_rev = a:args[0]
    endif

    if !exists('commit')
        " Follow base_rev back to when the current version was actually
        " committed.
        let cmd = printf("git log -1 --pretty=format:%%H %s -- %s",
            \ shellescape(base_rev), shellescape(a:fname))
        let commit = s:Strip(s:GetCmdOutput(cmd))
    endif

    let prefix = s:Strip(s:GetCmdOutput("git rev-parse --show-prefix"))
    let arg = shellescape(printf("%s:%s%s", commit, prefix, a:fname))
    call s:WriteCmdOutput("git show " . arg)

    if commit == ""
        let rev_info = "[index version]"
    else
        try
            let format = shellescape("--pretty=format:[%h|%an|%ar|%s]")
            let cmd = printf("git log -1 %s %s", format, commit)
            let rev_info = s:Strip(s:GetCmdOutput(cmd))
        catch
            let rev_info = s:rev_info_failed_msg
        endtry
    endif

    call s:SetBufName(printf("%s %s", a:fname, rev_info))
endfunction

function! s:HgUnmodified(fname, args)
    if empty(a:args)
        let rev_arg = ""
        let rev_range = ""
    else
        let rev_arg = "-r " . shellescape(a:args[0])
        let rev_range = "-r " . shellescape(a:args[0] . ":0")
    endif
    call s:WriteCmdOutput(printf("hg cat %s %s", rev_arg, shellescape(a:fname)))

    try
        let template = "[r:{rev}|br:{branches|nonempty}|{author|person}"
                   \ . "|{date|age}|{desc|firstline}]"
        let extra_cmd = printf("hg log -l 1 --template %s %s %s",
                             \ shellescape(template), rev_range,
                             \ shellescape(a:fname))
        let extra = s:Strip(s:GetCmdOutput(extra_cmd))
    catch
        "call s:Rethrow()
    endtry

    if !exists("extra") || extra == ""
        let extra = s:rev_info_failed_msg
    endif

    call s:SetBufName(printf("%s %s", a:fname, extra))
endfunction

function! s:SvnUnmodified(fname, args)
    if empty(a:args)
        let rev_arg = ""
    else
        let rev_arg = "-r " . shellescape(a:args[0])
    endif
    let cmd_args = printf("%s %s", rev_arg, shellescape(a:fname))
    " If fname has been added but not yet committed, this gives a rather
    " unhelpful error. This is kind of svn's fault.
    call s:WriteCmdOutput("svn cat " . cmd_args)

    try
        let log = s:GetCmdOutput("svn log -l 1 " . cmd_args)
        " The use of [^\x00] is a little weird. It seems to be the only way to
        " match "anything except newline" inside a string. Vim uses NUL
        " internally in place of the newline character, and [\n] seems to only
        " match the end of the string.
        let pieces = matchlist(log,
            \ '\v\n(r\d+) \| (.+) \| (.+) \| [^\x00]+(\n\n[^\x00]*)?')
        if !empty(pieces)
            " Date/time field looks like:
            " 2011-06-15 09:22:41 -0700 (Wed, 15 Jun 2011)
            let date_pieces = matchlist(pieces[3],
                \ '\v([-0-9]+) 0?([0-9:]+):\d\d ([-+0-9]+) \((.+)\)')
            let extra = printf("[%s|%s|%s %s|%s]", pieces[1], pieces[2],
                \ date_pieces[2], date_pieces[4], s:Strip(pieces[4]))
        endif
    catch
        " For debugging:
        "call s:Rethrow()
    endtry
    if !exists("extra")
        let extra = s:rev_info_failed_msg
    endif

    call s:SetBufName(printf("%s %s", a:fname, extra))
endfunction

function! s:P4Unmodified(fname, args)
    " TODO
    " * Set buffer name
    " * Allow rev arguments
    call s:WriteCmdOutput("p4 print -q " . a:fname)
endfunction

" }}}
" {{{ VCS COMMANDS

let s:git_help = "GitDiff [revision] - Diff against the specified revision "
    \ . "or, if no revision is given, the version in the index. Supports many "
    \ . "of the revision formats described in git-rev-parse(1)."
call s:AddVcsDiff("git", "GitDiff", "s:GitUnmodified", "?", s:git_help)

let s:hg_help = "HgDiff [revision] - Diff against the specified revision or, "
    \ . "if no revision is given, the version in the working directory's "
    \ . "parent."
call s:AddVcsDiff("hg", "HgDiff", "s:HgUnmodified", "?", s:hg_help)

let s:svn_help = "SvnDiff [revision] - Diff against the specified revision "
    \ . "or, if no revision is given, the version in HEAD. Supports revision "
    \ . "formats for svn's -r option."
call s:AddVcsDiff("svn", "SvnDiff", "s:SvnUnmodified", "?", s:svn_help)

let s:p4_help = "P4Diff - Diff against the latest revision."
call s:AddVcsDiff('p4', 'P4Diff', "s:P4Unmodified", "0", s:p4_help)

" }}}

let &cpo = s:save_cpo
