" Vim global plugin for editing encrypted files.
" Last Change: 2011 November 20
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
" This is a basic plugin for securely editing files encrypted with GnuPG.
" Measures are taken to ensure that the plaintext file is not stored on disk.
" However, it's difficult to be sure that these measures are sufficient in all
" cases. Use with caution.
"
" This plugin lacks many of the features of gnupg.vim
" (http://www.vim.org/scripts/script.php?script_id=661), but it's simpler,
" seems to have fewer quirks, and most importantly does not store the
" plaintext in a temporary file when passing it to gpg.
"
" Because pipes are used to transfer the plaintext to gpg, and Vim only
" supports pipes on Unix systems, this plugin only works on Unix systems. On
" other systems it should give an error, rather than falling back on the
" insecure temp file method.
"
" The following options are used to help ensure security:
"
"   noshelltemp (global)
"     Don't write buffer to a temp file when passing text to external
"     programs.
"
"   viminfo= (global)
"     Don't store anything in the viminfo file. Avoids storing things like
"     yanked text.
"
"   noswapfile (buffer local)
"     Don't write buffer info to disk.
"
" }}}
" {{{ USAGE
"
" It's not safe to edit encrypted files containing sensitive information while
" using arbitrary plugins and scripts. For this reason, this plugin is not
" loaded by default. To use this plugin (more) safely, Vim should be invoked
" this way:
"
"   vim -u <path to gpgsecure.vimrc>
"
" gpgsecure.vimrc should be distributed with the plugin, and can be customized
" to suit your needs. Consider adding an alias like this to your shell startup
" file (.bashrc, etc.):
"
"   alias svim='vim -u ~/.vim/gpgsecure.vimrc'
"
" By default, your .vimrc file will not be loaded, since it may not be safe to
" do so. You can change this by editing gpgsecure.vimrc, and you can make your
" .vimrc safer by conditionally leaving out unsafe items when
" g:loading_gpgsecure is defined.
"
" In addition, all other plugins will be skipped by default. Plugins you feel
" are safe can be enabled on a case-by-case basis in gpgsecure.vimrc.
"
" If you want to simply use this as a normal plugin and bypass these extra
" security measures, you can define g:loading_gpgsecure in your .vimrc.
" Obviously this is not advised.
"
" Any use of this plugin is strictly at your own risk. As the license says,
" there is no warranty, explicit or implied.
"
" }}}
" {{{ SETTINGS
"
" The following settings are available:
"
"   g:gpg_options
"     A string with options that will be passed to gpg for encrypting and
"     decrypting. Default: "--use-agent"
"
"   g:gpg_read_options
"     A string with options that will be passed to gpg for decrypting.
"     Default: "--decrypt"
"
"   g:gpg_write_options
"     A string with options that will be passed to gpg for encrypting.
"     Default: "--symmetric"
"
" }}}
" {{{ ISSUES
"
" * The stderr output from gpg is written to a temporary file in order for Vim
"   to retrieve it and report errors. This doesn't include the encrypted data,
"   but it may leak certain information. This information is probably not
"   particularly sensitive, but you should still be aware of it.
"
" * gpg will return an error result when the agent window is dismissed, even
"   though it can successfully fall back on using the tty. It's not clear that
"   this can be distinguished from real errors, so it's reported as an error
"   even though the decryption succeeds.
"
" }}}

if exists("loaded_gpgsecure") || !exists("loading_gpgsecure")
    finish
endif
let loaded_gpgsecure = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists("g:gpg_options")
    let g:gpg_options = "--use-agent"
endif
if !exists("g:gpg_read_options")
    let g:gpg_read_options = "--decrypt"
endif
if !exists("g:gpg_write_options")
    let g:gpg_write_options = "--symmetric"
endif

augroup GpgSecure
    autocmd!
    autocmd BufReadCmd *.gpg call s:ErrorWrapper("s:GpgRead", expand("<afile>"))
    autocmd BufWriteCmd *.gpg call s:ErrorWrapper("s:GpgWrite",
                                                \ expand("<afile>"))
augroup END

" {{{ Tools to support 'rethrow' in Vim

let s:rethrow_pattern = '\v\<SNR\>\d+_Rethrow>'

function! s:Rethrow()
    let except = v:exception

    " Save source info
    if !exists("s:rethrow_throwpoint") || v:throwpoint !~# s:rethrow_pattern
        let s:rethrow_throwpoint = v:throwpoint
    endif

    " Can't directly throw Vim exceptions (see :h try-echoerr), so use echoerr
    " instead, but strip off an existing echoerr prefix first.
    if except =~# '\v^Vim'
        echoerr substitute(except, '\v^Vim\(echoerr\):', "", "")
    endif

    throw except
endfunction

function! s:Throwpoint()
    if v:throwpoint =~# s:rethrow_pattern
        return s:rethrow_throwpoint
    else
        return v:throwpoint
    endif
endfunction

" }}}

function! s:ShellRead(cmd)
    return s:ShellCmd("read !" . a:cmd)
endfunction

function! s:ShellWrite(cmd)
    " This gives a Press Enter prompt unless silenced.
    return s:ShellCmd("silent write !" . a:cmd)
endfunction

function! s:ShellCmd(cmd)
    " Save stderr
    let temp = tempname()
    exec a:cmd . " 2> " . fnameescape(temp)
    let g:gpg_stderr = join(readfile(temp), "\n")
    call delete(temp)
    if v:shell_error != 0
        throw printf("shell error (%d): %s", v:shell_error, g:gpg_stderr)
    endif
endfunction

function! s:ErrorWrapper(func, ...)
    try
        call call(a:func, a:000)
    catch
        redraw
        echohl ErrorMsg
        echomsg "Error from: " . s:Throwpoint()
        echomsg v:exception
        echohl NONE
    endtry
endfunction

function! s:GpgRead(filename)
    let file_exists = glob(a:filename, 1) != ""

    call s:SecuritySettings()
    setlocal buftype=acwrite

    if file_exists
        let saved_undolevels = &undolevels
        set undolevels=-1
        try
            call s:ShellRead(
                \ printf("gpg --output - %s %s %s", g:gpg_options,
                       \ g:gpg_read_options, fnameescape(a:filename)))
            keepjumps 1 delete _
        catch
            bwipeout!
            call s:Rethrow()
        finally
            let &undolevels = saved_undolevels
        endtry
    else
        " This causes the usual [New File] message.
        exec "edit " . fnameescape(a:filename)
    endif

    " Save the current change number
    let b:gpg_change_nr = changenr()
endfunction

function! s:GpgWrite(filename)
    let same_file = resolve(a:filename) == resolve(expand("%"))
    let overwrite = v:cmdbang || &writeany
    let file_exists = glob(a:filename, 1) != ""

    if !same_file && !overwrite && file_exists
        echoerr "File exists (add ! to override)"
        " As long as we're in a :try block, this return shouldn't actually
        " be needed, but it doesn't hurt.
        return
    endif

    call s:ShellWrite(printf("gpg %s %s > %s", g:gpg_options,
                           \ g:gpg_write_options, fnameescape(a:filename)))

    if same_file || &cpo =~ '\V+'
        call s:ResetModified()
    endif
endfunction

function! s:SecuritySettings()
    " global settings
    if !has("filterpipe")
        throw "this Vim lacks the filterpipe feature required for secure " .
            \ "editing"
    endif
    set noshelltemp
    set viminfo=

    " local settings
    setlocal noswapfile
endfunction

" GoToChange goes to the buffer state just after the specified change number,
" which may be 0.
function! s:GoToChange(change)
    if a:change == changenr()
        return
    elseif a:change == 0
        silent undo 1
        silent undo
    else
        exec "silent undo " . a:change
    endif
endfunction

" ResetModified makes the current change the "unmodified" state for the buffer,
" and makes any previous "unmodified" state "modified". In other words, calling
" this after writing makes the undo state that corresponds with the on-disk file
" not show the [+] modified flag, but makes other undo states show it.
function! s:ResetModified()
    let cur_change = changenr()

    if cur_change != b:gpg_change_nr
        " make b:gpg_change_nr modified
        call s:GoToChange(b:gpg_change_nr)
        set modified
        call s:GoToChange(cur_change)
    endif

    let b:gpg_change_nr = cur_change
    setlocal nomodified
endfunction

let &cpo = s:save_cpo
