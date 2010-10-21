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
