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
" BUG: xxd isn't good at detecting write errors, therefore writing could fail
" while appearing to succeed.
"
" BUG: :saveas and :file don't work properly in a hex buffer. This could
" possibly be fixed by adding the BufFilePre autocmd.
"
" }}}

" XXX Work-around the Vim end-of-line bug. (Still necessary?)

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

function! s:HexToggle(bang)
    " The 'try' block turns errors into exceptions. See :help except-compat.
    try
        if &modified && a:bang != "!"
            " Cause a familiar error (unless 'autowriteall' is set, in which
            " case this succeeds as expected).
            edit
        endif

        if exists("b:hex_original_bufnr")
            " Already hex mode. Just show the original buffer, which will
            " (usually) wipeout this buffer, restoring original buffer
            " settings.
            if bufexists(b:hex_original_bufnr)
                exec printf("buffer%s %d", a:bang, b:hex_original_bufnr)
            else
                echoerr "original buffer no longer exists"
            endif
            return
        endif

        " This checks for empty filenames and non-existing files.
        if glob(expand("%")) == ""
            echoerr "file doesn't exist (write to a file first!)"
        endif

        " Set up the original buffer.

        " We don't need to change filetype, but for some reason syntax
        " highlighting gets lost if we don't set it when restoring settings.
        let saved_settings = [&modifiable, &filetype, &bufhidden]

        " We can't really notify the user of changes made in the original
        " buffer, so make it nonmodifiable as a safeguard. This will be
        " automatically reset when the hex window is closed.
        setlocal nomodifiable
        " Don't unload the original buffer, it loses undo history.
        setlocal bufhidden=hide

        " Create the new hex buffer.
        call HexNewBuffer(a:bang, saved_settings)
    catch
        " Restore original buffer settings.
        if exists("saved_settings")
            let [&l:modifiable, &l:filetype, &l:bufhidden] = saved_settings
        endif

        " Show the error message in a nice way.
        redraw
        echohl ErrorMsg
        echomsg v:exception
        echohl NONE
    endtry
endfunction

function! HexNewBuffer(bang, saved_settings)
    " Create and set up the new buffer
    let original_bufnr = bufnr("")
    let fname = expand("%")
    exec "enew" . a:bang
    try
        let b:hex_original_bufnr = original_bufnr
        set buftype=acwrite bufhidden=wipe
        exec printf("silent file %s [hex]", fnameescape(fname))
        augroup HexEdit
            let pathstr = string(fnamemodify(fname, ":p"))
            exec printf("au BufWriteCmd <buffer> call s:HexWrite(%s)",
                      \ pathstr)
            exec printf("au BufReadCmd <buffer> call s:HexRead(%s)",
                      \ pathstr)
            exec printf("au BufWinLeave <buffer> call " .
                      \ "s:HexRestore(%d, %s)",
                      \ original_bufnr, string(a:saved_settings))
        augroup END

        " Load the file from disk, via s:HexRead.
        edit
    catch
        " Restore original buffer, destroy the new buffer.
        let broken_bufnr = bufnr("")
        " For some reason, not silencing this prevents the final echo'ed error
        " message from being seen, even with a redraw before it.
        exec "silent buffer! " . original_bufnr
        if bufexists(broken_bufnr)
            exec "bwipeout! " . broken_bufnr
        endif
        call s:Rethrow()
    endtry
endfunction

function! s:HexWrite(fpath)
    try
        let target = expand("<afile>")
        let same_file = (target == expand("%"))

        if same_file
            " Redirect to the real file, not 'filename [hex]'
            let target = a:fpath
        endif

        " Don't overwrite an existing file unless forced.
        if !same_file && !v:cmdbang && glob(target) != ""
            " It seems like this should produce the expected error, but for
            " some reason it succeeds instead. No idea why.
            "exec "write " . fnameescape(target)
            echoerr "File exists (add ! to override)"
        endif

        exec "silent write !xxd -r > " . fnameescape(target)
        if v:shell_error != 0
            echoerr "failed to write file " . string(target)
        endif

        " Only reset 'modified' if the file being written is the same one
        " loaded in the buffer (e.g., using ':w' and not ':w otherfile'), or
        " if the '+' flag is included in 'cpoptions'.
        if same_file || stridx(&cpoptions, "+") >= 0
            set nomodified
        endif
    endtry
endfunction

" This is necessary to restore an unloaded buffer, or revert with :e.
function! s:HexRead(fpath)
    let undolevels = &undolevels
    try
        " Disabling undo during the read makes it so you can't undo back to an
        " empty buffer. Might also be faster.
        set undolevels=-1
        exec "silent read !xxd -g1 " . fnameescape(a:fpath)
        if v:shell_error != 0
            echoerr "failed to read file " . string(a:fpath)
        endif
        " :read leaves a blank line at the top.
        1 delete _
        set filetype=xxd
    finally
        let &undolevels = undolevels
    endtry
endfunction

function! s:HexRestore(bufnum, settings)
    if !bufexists(a:bufnum)
        " buffer's gone, nothing to do.
        return
    endif
    " Setting the current buffer here seems like it could be a problem.
    " Suppose two windows are open, one being the hex buffer and one being
    " unrelated. Closing the hex window should focus the unrelated window, not
    " the non-hex buffer. It turns out that, since this is called from the
    " BufWinLeave autocmd, the hex window is still open, and the buffer
    " presumably gets put into that window when it is activated, so it all
    " works out.
    exec "buffer! " . a:bufnum
    let [&l:modifiable, &l:filetype, &l:bufhidden] = a:settings
endfunction

command! -bar -bang HexToggle call s:HexToggle("<bang>")
