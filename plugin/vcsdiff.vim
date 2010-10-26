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
" }}}
" {{{ NOTES
"
" Known Bugs:
" * After doing the diff, if the original window is split, closing the diff
"   window only restores settings for one of the remaining diff windows.
"
" }}}
" {{{ DEFINITIONS

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

" }}}
" {{{ UTILITY FUNCTIONS

" s:Strip(str) returns a copy of str with leading and trailing whitespace
" removed.
function! s:Strip(str)
    return substitute(a:str, '\v^[ \t\r\n]*(.{-})[ \t\r\n]*$', '\1', "")
endfunction

" s:WriteCmdOutput(cmd) executes a command and writes the output to the
" current buffer without an extra empty line and without trashing registers.
" This currently assumes the buffer is initially empty, and doesn't handle
" errors as well as it could.
function! s:WriteCmdOutput(cmd)
    exec "read ! " . a:cmd
    " :read inserts below the cursor, leaving an empty line in a previously
    " empty buffer. Delete the line without saving it in a register.
    normal gg"_dd
endfunction

" s:ChFileDir changes directory to the directory containing the file.
function! s:ChFileDir(path)
    exe "cd " . fnamemodify(a:path, ":h")
endfunction

" There's no rethrow in vim, and the standard way to emulate it, by throwing
" v:exception, fails with vim errors (see :help rethrow). This is a
" work-around.
function! s:Rethrow()
    if v:exception =~# '\v^Vim'
        " Can't throw this directly
        echoerr v:exception
    endif
    throw v:exception
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
        throw "can't wrap to such a narrow width (" . a:width . " chars)"
    endif

    let words = split(a:str, '\v[ \t\n]+')
    let lines = []

    call add(lines, s:BuildLine(words, a:width, ""))

    while len(words)
        call add(lines, s:BuildLine(words, a:width, "  "))
    endwhile

    return join(lines, "\n")
endfunction

function! s:ErrorMsg(msg)
    echohl ErrorMsg
    echo a:msg
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
        exe "command! -nargs=" . a:nargs . " " . a:cmd_name .
            \ " call s:Diff('" . a:buffer_func . "', [<f-args>])"
    endif
endfunction

function! s:Diff(funcname, args)
    if s:HasDiffBuffer()
        call s:ErrorMsg("diff already active")
        return
    endif

    let saveddir = getcwd()
    " Error handling is tricky, but just being in a try block makes vim throw
    " errors instead of reporting and continuing. See :help except-compat.
    try
        " Gather info
        let filepath = expand("%:p")
        let filetype = &filetype
        let w:vcsdiff_restore = "diffoff|"
            \ . "setlocal"
            \ . (&diff ? " diff" : " nodiff")
            \ . (&scrollbind ? " scrollbind" : " noscrollbind")
            \ . " scrollopt=" . &scrollopt
            \ . (&wrap ? " wrap" : " nowrap")
            \ . " foldmethod=" . &foldmethod
            \ . " foldcolumn=" . &foldcolumn

        " Prepare starting buffer
        diffthis

        " Create and prepare new buffer.
        exec g:vcsdiff_new_win_prefix . " new"
        try
            " See :help special-buffers. For bufhidden, only hide or wipe seem
            " to make any sense. Otherwise the buffer is unloaded and anything
            " that's left isn't useful.
            set buftype=nofile bufhidden=wipe
            exec "call " . a:funcname . "('" . filepath . "', a:args)"
            setlocal nomodifiable
            let &filetype = filetype
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
        " Undo any changes made to the original buffer and window, then
        " propagate the error so it can be reported.
        call s:Undiff()
        call s:Rethrow()

    finally
        " Clean up
        exec "cd " . saveddir
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
    " There should actually only be one window with such a command, but if
    " there are others (perhaps due to bugs) it's probably best to go ahead
    " and get rid of them.
    for i in range(1, last_win)
        exec i . "wincmd w"
        if exists("w:vcsdiff_restore")
            exec w:vcsdiff_restore
            unlet w:vcsdiff_restore
        endif
    endfor
    exec cur_win . "wincmd w"
endfunction

function! s:List()
    echo "Supported Version Control Systems (* = currently enabled)"
    for [name, cmds] in items(s:command_names)
        if index(s:include, name) != -1
            let used = "* "
        else
            let used = "  "
        endif
        echo used . name . " (" . join(cmds, ", ") . ")"
    endfor
endfunction

function! s:Help(...)
    if empty(a:000)
        let cmds = keys(s:command_help)
    else
        let cmds = copy(a:000)
    endif
    call sort(cmds)
    for cmd in cmds
        let help = get(s:command_help, cmd, "")
        if len(help) == 0
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

command! VcsDiffList call s:List()
command! -nargs=* -complete=custom,s:HelpCompletion
    \ VcsDiffHelp call s:Help(<f-args>)

" }}}
" {{{ VCS FUNCTIONS

function! s:GitUnmodified(path, args)
    if empty(a:args)
        let revision = ""
        let from = " from index"
    else
        let revision = a:args[0]
        let from = " from " . revision
    endif
    call s:ChFileDir(a:path)
    let prefix = s:Strip(system("git rev-parse --show-prefix"))
    if v:shell_error != 0
        throw "git rev-parse command failed. Not a git repo?"
    endif
    let fname = fnamemodify(a:path, ":t")
    call s:WriteCmdOutput("git show \"" . revision . ":" . prefix . fname .
                        \ "\"")
    call s:SetBufName(fname . from)
endfunction

function! s:HgUnmodified(path, args)
    if empty(a:args)
        let rev_arg = ""
        let rev = "parent"
    else
        let rev_arg = " -r " . a:args[0]
        let rev = "rev " . a:args[0]
    endif
    call s:ChFileDir(a:path)
    let fname = fnamemodify(a:path, ":t")
    call s:WriteCmdOutput("hg cat" . rev_arg . " " . fname)
    call s:SetBufName(fname . " at " . rev)
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

" }}}
