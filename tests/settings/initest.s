; The VICE test of src/inc/ini.inc (tests/settings/ini.py): the three
; routines behind a jump table at $2000, the buffer at $3000 (the test
; sets iniBase and iniMax to it).

        .include "geos.inc"


        .segment "CODE"
        jmp IniFind             ; $2000
        jmp IniSet              ; $2003
        jmp IniDel              ; $2006
        .word iniLen            ; $2009: where iniLen is
        .word iniSkip           ; $200B: where iniSkip is
        .word iniBase           ; $200D: where iniBase is (the test sets
        .word iniMax            ; $200F: and iniMax: $3000, 1023)

        .include "ini.inc"
