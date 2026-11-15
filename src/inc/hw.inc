; C64 hardware registers used by GeoUltra.

CPU_PORT        = $01
RAM_ALL         = $30     ; all RAM
RAM_IO          = $35     ; RAM with I/O at $D000
ROM_ALL         = $37     ; BASIC, I/O, Kernal

; VIC-II
vicSpr0X        = $D000
vicSpr0Y        = $D001
vicSprXMsb      = $D010
vicCtrl1        = $D011
vicRaster       = $D012
vicSprEnable    = $D015
vicCtrl2        = $D016
vicMemPtr       = $D018
vicIrq          = $D019
vicIrqMask      = $D01A
vicSprMulti     = $D01C
vicBorder       = $D020
vicBackground   = $D021
vicSpr0Color    = $D027

; SID
sidPotX         = $D419
sidPotY         = $D41A

; CIA
cia1PortA       = $DC00
cia1PortB       = $DC01
cia1DdrA        = $DC02
cia1Icr         = $DC0D
cia2PortA       = $DD00
cia2DdrA        = $DD02
cia2Icr         = $DD0D

; Megabyter cartridge (CRT type 86)
mbBank          = $DE00
mbCtrl          = $DE02
MB_ON8K         = $00     ; EXROM active, GAME inactive: ROML at $8000
MB_OFF          = $02

; REU
reuStatus       = $DF00
reuCmd          = $DF01
reuC64          = $DF02
reuAddr         = $DF04   ; 3 bytes
reuLen          = $DF07
reuCtrl         = $DF0A
REU_STASH       = $90     ; execute now, C64 -> REU
REU_FETCH       = $91     ; execute now, REU -> C64
REU_VERIFY      = $93     ; execute now, compare (writes nothing)
REU_FETCH_FF00  = $81     ; execute on a write to $FF00, REU -> C64
REU_TRIGGER     = $FF00
