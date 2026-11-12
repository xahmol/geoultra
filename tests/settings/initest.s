; The VICE test of src/inc/ini.inc (tests/settings/ini.py): the three
; routines behind a jump table at $2000, the buffer at $3000.

        .include "geos.inc"

INI_BUF         = $3000
INI_MAX         = 1023

        .segment "CODE"
        jmp IniFind             ; $2000
        jmp IniSet              ; $2003
        jmp IniDel              ; $2006
        .word iniLen            ; $2009: where iniLen is
        .word iniSkip           ; $200B: where iniSkip is

        .include "ini.inc"
