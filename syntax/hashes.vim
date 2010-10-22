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
" This is a syntax file for hash files like those generated from md5sum,
" sha1sum, etc. It is intended to make it easy to compare hashes.
"
" This syntax file is unusual in that it doesn't know ahead of time what the
" syntax elements (hashes in this case) are going to be. It reads them from
" the file and sets syntax elements accordingly. If the file is modified, the
" syntax has to be reloaded to pick up the changes. The command HashRefresh
" can be used to do this.
"
" There are three modes for highlighting hashes. The 'normal' mode alternates
" different colors for new hashes from the top of the file down. The 'unique'
" mode highlights only the hashes that only appear once to make them easy to
" spot. The 'dupes' mode is the opposite: it highlights only the hashes that
" appear more than once. The mode is selected with the HashMode command.
"
" For the purposes of visually comparing files by hash, it's useful to sort
" the file. The HashSort command is equivalent to :sort followed by
" :HashRefresh.
"
" }}}
" {{{ OPTION & COMMAND SUMMARY
"
" The following options are available:
"
" g:hash_groups
"
"   This is a list of the highlight groups used for highlighting hash values
"   in 'normal' mode. Each new hash value uses the next group in this list,
"   wrapping around to the beginning once the end is reached. Since the
"   actual colors will depend on your colorscheme, you may need to override
"   the default in order to get distinct colors.
"
" g:hash_mode
"
"   This is the default mode to use when opening a hash file. It should be one
"   of the strings 'normal', 'unique', or 'dupes'.
"
" The following commands may be used:
"
" HashRefresh
"
"   Reload the hash syntax groups from scratch. This re-assigns colors to hash
"   values, so it's good to use if you change the file.
"
" HashSort
"
"   Sorts the lines in the file then refreshes the syntax. Same as doing :sort
"   followed by :HashRefresh.
"
" HashMode
"
"   Without arguments, display the current highlighting mode. Otherwise,
"   should be given one argument specifying the highlighting mode to switch to
"   (normal, unique, or dupes).
"
" }}}

if exists('b:current_syntax')
    finish
endif

if exists('g:hash_groups')
    let s:groups = g:hash_groups
else
    let s:groups = ['Comment', 'Constant', 'Identifier', 'Statement', 'PreProc']
endif

if exists('g:hash_mode')
    let b:hash_mode = g:hash_mode
else
    let b:hash_mode = 'normal'
endif

let b:hash_color_index = 0
let b:hash_counts = {} " { 'hash' : occurrences }

function! s:NextGroup()
    let g = s:groups[b:hash_color_index]
    let b:hash_color_index = (b:hash_color_index + 1) % len(s:groups)
    return g
endfunction

function! s:Reset()
    for hash in keys(b:hash_counts)
        exe 'highlight link Hash' . hash . ' NONE'
        exe 'syntax clear Hash' . hash
    endfor
    let b:hash_color_index = 0
    let b:hash_counts = {}
endfunction

function! s:HashRefresh()
    call s:Reset()

    let last_line = line('$')
    for i in range(1, last_line)
        let line = getline(i)
        let hash = matchstr(line, '\v^\x{32,}')
        if hash == ''
            continue
        endif

        let cnt = get(b:hash_counts, hash, 0)

        " normal mode is handled in the loop so the colors alternate down
        " the file
        if cnt == 0 && b:hash_mode == 'normal'
            exe 'syntax keyword Hash' . hash . ' ' . hash
            exe 'highlight link Hash' . hash . ' ' . s:NextGroup()
        endif

        let b:hash_counts[hash] = cnt + 1
    endfor

    if b:hash_mode != 'normal'
        for [hash, cnt] in items(b:hash_counts)
            if (cnt == 1 && b:hash_mode == 'unique') ||
                \ (cnt > 1 && b:hash_mode == 'dupes')
                exe 'syntax keyword Hash' . hash . ' ' . hash
                exe 'highlight link Hash' . hash . ' Todo'
            endif
        endfor
    endif
endfunction

function! s:ChangeMode(new_mode)
    if a:new_mode == ''
        echo b:hash_mode
        return
    endif
    if a:new_mode !~# '\v^(normal|dupes|unique)$'
        echohl WarningMsg
        echo 'invalid hash mode: "' . a:new_mode . '"'
        echohl None
        return
    endif
    let b:hash_mode = a:new_mode
    call s:HashRefresh()
endfunction

" Used for command completion.
function! s:HashModes(arglead, cmdline, cursorpos)
    return "normal\ndupes\nunique"
endfunction

command! -buffer -bar HashRefresh call s:HashRefresh()
command! -buffer -bar HashSort sort|call s:HashRefresh()
command! -buffer -bar -nargs=? -complete=custom,s:HashModes
    \ HashMode call s:ChangeMode(<q-args>)

syntax match String '\v [ *]\zs.+\ze$'

HashRefresh

let b:current_syntax = 'hashes'
