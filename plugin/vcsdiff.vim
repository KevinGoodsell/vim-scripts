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
        throw printf("can't wrap to such a narrow width (%d chars)", a:width)
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
        exec printf("command! -nargs=%s %s call s:Diff('%s', [<f-args>])",
                  \ a:nargs, a:cmd_name, a:buffer_func)
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
        let w:vcsdiff_restore = "diffoff|"
            \ . "setlocal"
            \ . (&diff ? " diff" : " nodiff")
            \ . (&scrollbind ? " scrollbind" : " noscrollbind")
            \ . " scrollopt=" . &scrollopt
            \ . (&wrap ? " wrap" : " nowrap")
            \ . " foldmethod=" . &foldmethod
            \ . " foldcolumn=" . &foldcolumn

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
        " Undo any changes made to the original buffer and window, then
        " propagate the error so it can be reported.
        call s:Undiff()
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
            let used = "*"
        else
            let used = " "
        endif
        echo printf("%s %s (%s)", used, name, join(cmds, ", "))
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

function! s:GitUnmodified(fname, args)
    if empty(a:args)
        let revision = ""
        let from = " from index"
    else
        let revision = a:args[0]
        let from = " from " . revision
    endif
    try
        let prefix = s:Strip(s:GetCmdOutput("git rev-parse --show-prefix"))
    catch
        throw "git rev-parse command failed. Not a git repo?"
    endtry
    let arg = shellescape(printf("%s:%s%s", revision, prefix, a:fname))
    call s:WriteCmdOutput("git show " . arg)
    call s:SetBufName(a:fname . from)
endfunction

function! s:HgUnmodified(fname, args)
    if empty(a:args)
        let rev_arg = ""
        let rev = "parent"
    else
        let rev_arg = "-r " . shellescape(a:args[0])
        let rev = "rev " . a:args[0]
    endif
    call s:WriteCmdOutput(printf("hg cat %s %s", rev_arg,
                               \ shellescape(a:fname)))
    call s:SetBufName(printf("%s at %s", a:fname, rev))
endfunction

function! s:SvnUnmodified(fname, args)
    if empty(a:args)
        let rev_arg = ""
        let rev = "HEAD"
    else
        let rev_arg = "-r " . shellescape(a:args[0])
        let rev = "rev " . a:args[0]
    endif
    call s:WriteCmdOutput(printf("svn cat %s %s", rev_arg,
                               \ shellescape(a:fname)))
    call s:SetBufName(printf("%s at %s", a:fname, rev))
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

" }}}
