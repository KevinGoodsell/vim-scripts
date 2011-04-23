" Vim global plugin for toggling hex-editing mode
" Last Change: 2011 Apr 22
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
" USAGE: This plugin adds a command, HexToggle, which switches the current
" buffer to "hex mode", or switches back if hex mode was already active. While
" in hex mode, you can make edits to the byte values, revert changes with :e,
" and write the buffer with :w or :w <otherfile>.
"
" BEWARE!!! You cannot insert or remove bytes in hex mode (except at the end
" of the buffer). This won't produce any error, but it will probably corrupt
" the output file in strange ways.
"
" BEWARE!!! You cannot change bytes by editing the ASCII values on the right.
" this will have no effect.
"
" These are limitations of the hex dumping/reading program, xxd. See the xxd
" documentation for full details about its quirks.
"
" Be very careful about the end of the file! Vim can sometimes add or remove a
" final end-of-line. The 'binary' and 'endofline' options mostly determine
" when this happens, but there's also a Vim bug that can cause the first write
" following an unrelated read to drop the final end-of-line, if the read
" buffer lacked a final end-of-line. Writing the buffer a second time repairs
" the error. All of this confusion can be avoided by writing while in hex
" mode, but this also leaves you at the mercy of xxd's relatively error-prone
" and non-recoverable file writing.
"
" MORE DETAILS: "Toggling" hex mode on actually creates a new buffer that
" replaces the current buffer in the window. The original buffer remains
" intact, and can be accessed with commands like :sbuffer. However, the
" original buffer has 'nomodifiable' set, because changes made to it cannot be
" picked up in the hex buffer. 'modifiable' is automatically reset to its old
" value when the hex buffer is closed.
"
" The hex buffer is automatically destroyed when it is hidden or unloaded.
" Toggling out of hex mode is actually the same as doing :buffer <original
" buffer>, as long as that buffer actually still exists.
"
" The advantage of using a new buffer is that undo doesn't try to switch the
" text back from hex to the original text (which would completely break syntax
" highlighting and writing via xxd). Also, the original buffer's undo history
" remains intact if you switch back to it without writing (as long as it's not
" unloaded -- 'bufhidden' is set to hide to make this work, and the original
" value is restored when exiting hex mode).
"
" BUG: xxd isn't good at detecting write errors, therefore writing could fail
" while appearing to succeed.
"
" BUG: :saveas and :file don't work properly in a hex buffer. This could
" possibly be fixed by adding the BufFilePre autocmd.
"
" }}}

if exists("loaded_hexedit")
    finish
endif
let loaded_hexedit = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists("g:hex_statusline")
    let g:hex_statusline = "%<%f %m%r%=%{b:hex_status_info}  %-14.(%l,%c%V%) %P"
endif

" {{{ UTILITY FUNCTIONS

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

" Vim's printf gets field widths wrong when the characters going into the
" field are multi-byte (in the same way it gets strlen wrong). This can be
" used instead. The optional third argument is false for left-aligning within
" the field (the default), true for right-aligning.
function! s:PadString(str, width, ...)
    if a:0 > 0
        let right_align = a:1
    else
        let right_align = 0
    endif

    let len = strlen(substitute(a:str, '.', "x", "g"))
    let pad = max([0, a:width - len])
    if right_align
        return repeat(" ", pad) . a:str
    else
        return a:str . repeat(" ", pad)
    endif
endfunction

" }}}
" {{{ HEX TOGGLING

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
        let b:hex_status_info = ""
        set buftype=acwrite bufhidden=wipe
        let &l:statusline = g:hex_statusline
        exec printf("silent file %s [hex]", fnameescape(fname))

        " Some ideas here are borrowed from the matchit plugin.
        nnoremap <buffer> <silent> % :<C-U>call <SID>JumpMatch("n")<CR>
        vnoremap <buffer> <silent> % :<C-U>call <SID>JumpMatch("v")<CR>
        " Supporting operator-pending mode is probably more trouble than it's
        " worth.
        "onoremap <buffer> <silent> % :<C-U>call <SID>JumpMatch("o")<CR>

        augroup HexEdit
            let pathstr = string(fnamemodify(fname, ":p"))
            exec printf("au BufWriteCmd <buffer> call s:HexWrite(%s)",
                      \ pathstr)
            exec printf("au BufReadCmd <buffer> call s:HexRead(%s)",
                      \ pathstr)
            exec printf("au BufWinLeave <buffer> call " .
                      \ "s:HexRestore(%d, %s)",
                      \ original_bufnr, string(a:saved_settings))
            autocmd CursorMoved <buffer> call s:CursorMoved()
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

" }}}
" {{{ AUTOCMD FUNCTIONS

function! s:HexWrite(fpath)
    try
        let target = expand("<afile>:p")
        let same_file = (target == expand("%:p"))

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
        keepjumps 1 delete _
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
    " This would be nice, but we can't be sure which buffer we're on.
    "let [&l:modifiable, &l:filetype, &l:bufhidden] = a:settings
    call setbufvar(a:bufnum, "&modifiable", a:settings[0])
    call setbufvar(a:bufnum, "&filetype", a:settings[1])
    call setbufvar(a:bufnum, "&bufhidden", a:settings[2])
endfunction

function! s:CursorMoved()
    let byte_info = s:ByteInfo()
    call s:SetStatus(byte_info)
    call s:HighlightMatch(byte_info)
endfunction

" }}}
" {{{ EDITING FEATURES

function! s:MakeByteNames()
    " These encodings support all values from 0 to 255. Not exhaustive.
    if &encoding =~ '\v^(utf-|ucs-|iso-8859-|latin1)'
        let s:conversion_expr = "nr2char(v:val)"
    else
        let s:conversion_expr = "'----'"
    endif

    return [
        \ "NUL", "SOH", "STX", "ETX",   "EOT", "ENQ", "ACK", "BEL",
        \ "BS",  "HT",  "LF",  "VT",    "FF",  "CR",  "SO",  "SI",
        \ "DLE", "DC1", "DC2", "DC3",   "DC4", "NAK", "SYN", "ETB",
        \ "CAN", "EM",  "SUB", "ESC",   "FS",  "GS",  "RS",  "US",
        \ "SP"] + map(range(0x21, 0x7E), "nr2char(v:val)") + [
        \ "DEL",
        \ "PAD", "HOP", "BPH", "NBH",   "IND", "NEL", "SSA", "ESA",
        \ "HTS", "HTJ", "VTS", "PLD",   "PLU", "RI",  "SS2", "SS3",
        \ "DCS", "PU1", "PU2", "STS",   "CCH", "MW",  "SPA", "EPA",
        \ "SOS", "SGCI","SCI", "CSI",   "ST",  "OSC", "PM",  "APC",
        \ "NBSP"] + map(range(0xA1, 0xAC), s:conversion_expr) + [
        \ "SHY"] + map(range(0xAE, 0xFF), s:conversion_expr)
endfunction

let s:byte_names = s:MakeByteNames()
augroup HexEdit
    autocmd EncodingChanged * let s:byte_names = s:MakeByteNames()
augroup END

" For reference, column numbers and what it looks like at higher addresses:
"           1         2         3         4         5         6         7
" 01234567890123456789012345678901234567890123456789012345678901234567890123
" ffffff0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
" 10000000:00 00 00 ....

" This is a quick way to get the next byte offset from the cursor position.
let s:cursor_byte = repeat([0], 9) + map(range(16*3), "v:val / 3") + [0, 0]
    \ + range(16)

" Returns a list of 3 items:
" 0: The offset within the file of the next byte after the cursor position.
" 1: The cursor column where the next byte begins in the hex section.
" 2: The cursor column where the next byte occurs in the ASCII section.
function! s:ByteInfo()
    let line = getline(".")
    let matches = matchlist(line[:57], '\v^(\x{7,8}): ?(%(\x{2} ){1,16}) +')
    if empty(matches)
        return []
    endif
    let [full, addrpart, hexpart] = matches[:2]
    let asciipart = line[58:]
    if len(full) + len(asciipart) != len(line) || len(line) > 74
        return []
    endif
    let baseaddr = str2nr(addrpart, 16)

    let cursor = col(".")
    if cursor >= len(s:cursor_byte)
        return []
    endif

    let byte_offset = s:cursor_byte[cursor]
    let hex_pos = 10 + byte_offset * 3
    let asc_pos = 59 + byte_offset
    return [baseaddr + byte_offset, hex_pos, asc_pos]
endfunction

function! s:SetStatus(byte_info)
    let status_format = "%10s %4s %-4s"
    if empty(a:byte_info)
        let b:hex_status_info = printf(status_format, "??????????", '----',
                                     \ '----')
        return
    endif

    let [address, hex_pos, asc_pos] = a:byte_info
    let line = getline(".")
    let hexstr = line[hex_pos-1:hex_pos]
    let addrval = printf("0x%08x", address)
    if hexstr == "  "
        let hexval = "----"
        let ascval = "----"
    else
        let byteval = str2nr(hexstr, 16)
        let hexval = printf("0x%02x", byteval)
        let ascval = s:PadString(s:byte_names[byteval], 4)
    endif
    let b:hex_status_info = printf(status_format, addrval, hexval, ascval)
endfunction

function! s:HighlightMatch(byte_info)
    3match none

    if empty(a:byte_info)
        return
    endif

    let [address, hex_pos, asc_pos] = a:byte_info
    let cursor = col(".")
    let line = getline(".")
    if line[hex_pos-1] !~ '\x'
        return
    endif
    if cursor == asc_pos || cursor == hex_pos || cursor == hex_pos + 1
        let line_num = line(".")
        let pattern = printf('/\v(%%%dl%%%dc)|(%%%dl%%%dc)/', line_num, hex_pos,
                           \ line_num, asc_pos)
        exec "3match MatchParen " . pattern
    endif
endfunction

function! <SID>JumpMatch(mode)
    " This is another trick from matchit.vim. When a command is begun in
    " visual mode, and the range is deleted, visual mode is canceled and the
    " cursor is left at the earlier end of the visual range. When visual mode
    " is canceled with ESC, the cursor is left at the ending point. We are in
    " the former situation, and need to be in the later.
    if a:mode == "v"
        exec "normal! gv\<Esc>"
    endif

    let byte_info = s:ByteInfo()
    if empty(byte_info)
        if a:mode == "v"
            normal gv
        endif
        return
    endif

    " Save the current position in the jumplist.
    normal m'
    let [address, hex_pos, asc_pos] = byte_info
    let cursor = col(".")
    if cursor <= hex_pos + 1
        call cursor(0, asc_pos)
    else
        call cursor(0, hex_pos)
    endif

    if a:mode == "v"
        " Executing commands loses the visual selection, so restore it.
        normal m'gv``
    endif
endfunction

" }}}

if !exists(":HexToggle")
    command -bar -bang HexToggle call s:HexToggle("<bang>")
endif

let &cpo = s:save_cpo
