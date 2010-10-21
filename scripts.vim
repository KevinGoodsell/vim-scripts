
let s:line1 = getline(1)

if s:line1 =~ '\v^\x{32,} [ *]'
    set ft=hashes
endif
