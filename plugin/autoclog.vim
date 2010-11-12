" Vim global plugin for logging autocmds
" Last Change: 2010 Nov 11
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
" I find Vim plugin development very frustrating sometimes. Usually this is
" because I can't figure out what autocmds are executed under what
" circumstances, or in what order things are happening. This plugin is
" intended to help make autocmd events more transparent.
"
" This plugin adds one command, AutoCmdLog, which should be followed by a
" command. The provided command is executed with autocmds (and messages)
" logged into register 'a'.
"
" You can set g:autoclog_logged_cmds to a list of autocmd names you want
" logged. Certain commands won't work, and may cause serious breakage --
" notably the *Cmd commands (see :help Cmd-event), because they replace
" normal functionality.
"
" g:autoclog_items is a list of items to include in the log message for each
" autocmd. It is a list of pairs (each pair being a two-item list) where the
" first item is a label and the second is a string that will be evaluated with
" eval(). You can replace the defaults entirely by defining g:autoclog_items.
"
" If you want to keep the default log items but add more, use
" g:autoclog_items_extra. This has the same format as g:autoclog_items, and
" its items will be added to the end of each logged command.
"
" }}}

if exists("loaded_autoclog")
    finish
endif
let loaded_autoclog = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists("g:autoclog_items")
    let g:autoclog_items = [
        \ ["%", "expand('%')"],
        \ ["winnr", "winnr()"],
        \ ["<afile>", "expand('<afile>')"],
        \ ["<abuf>", "expand('<abuf>')"],
        \ ["<amatch>", "expand('<amatch>')"],
    \ ]
endif

if !exists("g:autoclog_items_extra")
    let g:autoclog_items_extra = []
endif

if !exists("g:autoclog_logged_cmds")
    let g:autoclog_logged_cmds = [
        \ "BufNewFile",
        \ "BufReadPre",
        \ "BufReadPost",
        \ "FileReadPre",
        \ "FileReadPost",
        \ "FilterReadPre",
        \ "FilterReadPost",
        \ "StdinReadPre",
        \ "StdinReadPost",
        \ "BufWritePre",
        \ "BufWritePost",
        \ "FileWritePre",
        \ "FileWritePost",
        \ "FileAppendPre",
        \ "FileAppendPost",
        \ "FilterWritePre",
        \ "FilterWritePost",
        \ "BufAdd",
        \ "BufDelete",
        \ "BufWipeout",
        \ "BufFilePre",
        \ "BufFilePost",
        \ "BufEnter",
        \ "BufLeave",
        \ "BufWinEnter",
        \ "BufWinLeave",
        \ "BufUnload",
        \ "BufHidden",
        \ "BufNew",
        \ "SwapExists",
        \ "FileType",
        \ "Syntax",
        \ "EncodingChanged",
        \ "TermChanged",
        \ "VimEnter",
        \ "GUIEnter",
        \ "TermResponse",
        \ "VimLeavePre",
        \ "VimLeave",
        \ "FileChangedShell",
        \ "FileChangedShellPost",
        \ "FileChangedRO",
        \ "ShellCmdPost",
        \ "ShellFilterPost",
        \ "FuncUndefined",
        \ "SpellFileMissing",
        \ "SourcePre",
        \ "VimResized",
        \ "FocusGained",
        \ "FocusLost",
        \ "CursorHold",
        \ "CursorHoldI",
        \ "CursorMoved",
        \ "CursorMovedI",
        \ "WinEnter",
        \ "WinLeave",
        \ "TabEnter",
        \ "TabLeave",
        \ "CmdwinEnter",
        \ "CmdwinLeave",
        \ "InsertEnter",
        \ "InsertChange",
        \ "InsertLeave",
        \ "ColorScheme",
        \ "RemoteReply",
        \ "QuickFixCmdPre",
        \ "QuickFixCmdPost",
        \ "SessionLoadPost",
        \ "MenuPopup",
        \ "User",
    \ ]
endif

function! s:AutoCmd(name)
    let pieces = []
    for [label, expr] in g:autoclog_items + g:autoclog_items_extra
        let piece = printf("%s=%s", label, eval(expr))
        call add(pieces, piece)
    endfor
    echomsg printf("autocmd %s, %s", a:name, join(pieces, ", "))
endfunction

function! s:AddAutoCmd(name)
    exec printf("autocmd AutoCLog %s * call s:AutoCmd(%s)", a:name,
              \ string(a:name))
endfunction

function! s:ExecWithLogging(cmd)
    " Initialize group
    augroup AutoCLog
        autocmd!
    augroup END

    " Create the logging autocmds.
    for c in g:autoclog_logged_cmds
        call s:AddAutoCmd(c)
    endfor

    try
        " Redirect and run the command.
        redir @a>
        silent exec a:cmd
        redir END

    finally
        " Remove autocmds.
        augroup AutoCLog
            autocmd!
        augroup END
    endtry
endfunction

command! -nargs=1 AutoCmdLog call s:ExecWithLogging(<q-args>)

let &cpo = s:save_cpo
