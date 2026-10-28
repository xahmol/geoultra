; GEOS 64 2.0 interface: zero page, system variables and constants that
; applications are compiled against. Addresses from HG2G2022 and
; inc/geossym.inc of the reassembled kernal (mist64/geos, Maciej
; Witkowiak); see docs/ARCHITECTURE.md, "Attribution".

; Pseudo-registers r0-r15
r0      = $02
r0L     = $02
r0H     = $03
r1      = $04
r1L     = $04
r1H     = $05
r2      = $06
r2L     = $06
r2H     = $07
r3      = $08
r3L     = $08
r3H     = $09
r4      = $0A
r4L     = $0A
r4H     = $0B
r5      = $0C
r5L     = $0C
r5H     = $0D
r6      = $0E
r6L     = $0E
r6H     = $0F
r7      = $10
r7L     = $10
r7H     = $11
r8      = $12
r8L     = $12
r8H     = $13
r9      = $14
r9L     = $14
r9H     = $15
r10     = $16
r10L    = $16
r10H    = $17
r11     = $18
r11L    = $18
r11H    = $19
r12     = $1A
r12L    = $1A
r12H    = $1B
r13     = $1C
r13L    = $1C
r13H    = $1D
r14     = $1E
r14L    = $1E
r14H    = $1F
r15     = $20
r15L    = $20
r15H    = $21

; Kernal zero page variables
curPattern      = $22   ; word: pointer to the 8-byte fill pattern
dispBufferOn    = $2F
mouseOn         = $30
msePicPtr       = $31   ; word
windowTop       = $33
windowBottom    = $34
leftMargin      = $35   ; word
rightMargin     = $37   ; word
pressFlag       = $39
mouseXPos       = $3A   ; word
mouseYPos       = $3C

; System variables
appMain         = $849B
intTopVector    = $849D
intBotVector    = $849F
mouseVector     = $84A1
keyVector       = $84A3
inputVector     = $84A5
mouseFaultVec   = $84A7
otherPressVec   = $84A9
faultData       = $84B6
mouseTop        = $84B8
mouseBottom     = $84B9
mouseLeft       = $84BA   ; word
mouseRight      = $84BC   ; word
maxMouseSpeed   = $8501
minMouseSpeed   = $8502
mouseAccel      = $8503
keyData         = $8504
mouseData       = $8505
inputData       = $8506
mouseSpeed      = $8507
screencolors    = $851E

; Memory areas
OS_VARS         = $8000
SCREEN_BASE     = $A000
BACK_SCR_BASE   = $6000
SPRITE_PICS     = $8A00
COLOR_MATRIX    = $8C00
MOUSE_BASE      = $FE80
InitMouse       = MOUSE_BASE
SlowMouse       = MOUSE_BASE + 3
UpdateMouse     = MOUSE_BASE + 6

; Constants
ST_WR_FORE      = $80     ; dispBufferOn
ST_WR_BACK      = $40
KEYPRESS_BIT    = $80     ; pressFlag
INPUT_BIT       = $40
MOUSE_BIT       = $20
MOUSEON_BIT     = $80     ; mouseOn
MENUON_BIT      = $40
ICONSON_BIT     = $20
SC_PIX_WIDTH    = 320
SC_PIX_HEIGHT   = 200
