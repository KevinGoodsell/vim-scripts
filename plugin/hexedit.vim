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
" Vim is actually pretty bad for hex editing. This might be handy for quick,
" simple editing or for just reviewing (not changing) bytes, but you should
" use something more specialized for serious hex work.
"
" BUG: Switching from hex mode to normal mode can add or delete a final
" newline character. This is very confusing because you can't really tell when
" it happens, and writing the file in normal mode will sometimes spontaneously
" change the situation again. This is partly due to Vim's expected handling of
" newlines at the end of a file (see :help 'endofline'), but it seems like
" there may also be a Vim bug at play.
"
" BUG: Editing multiple buffers with differing final-end-of-line situations
" doesn't work right. This seems to be a Vim bug.
"
" }}}

function! s:Xxd(args)
    let bin = &binary
    try
        setlocal binary
        exec "%!xxd " . a:args
    finally
        let &l:binary = bin
    endtry
endfunction

function! s:StartHex()
    call s:Xxd("-g1")
    if v:shell_error != 0
        echo "xxd command failed"
        return
    endif
    let b:hex_saved_opts = [&filetype, &buftype]
    setlocal filetype=xxd buftype=acwrite
    augroup HexEdit
        au BufWriteCmd <buffer> call s:HexWrite()
    augroup END
endfunction

function! s:EndHex()
    call s:Xxd("-r")
    if v:shell_error != 0
        echo "xxd command failed"
    endif
    let [&l:filetype, &l:buftype] = b:hex_saved_opts
    unlet b:hex_saved_opts
    au! HexEdit * <buffer>
endfunction

function! s:HexToggle()
    let mod = &modified
    if exists("b:hex_saved_opts")
        call s:EndHex()
    else
        call s:StartHex()
    endif
    let &l:modified = mod
endfunction

function! s:HexWrite()
    let temp = fnameescape(tempname())
    exec "silent w " . temp
    try
        " Using redirection forces truncation of the file. xxd doesn't
        " truncate otherwise.
        exec printf("silent !xxd -r %s > %s", temp,
                  \ fnameescape(expand("<afile>")))
        if v:shell_error == 0
            setlocal nomodified
        endif
    finally
        call delete(temp)
    endtry
endfunction

command! -bar HexToggle call s:HexToggle()
