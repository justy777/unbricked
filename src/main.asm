INCLUDE "include/hardware.inc"

; Tile IDs
DEF BRICK_LEFT EQU $05
DEF BRICK_RIGHT EQU $06
DEF BLANK_TILE EQU $08
DEF DIGIT_OFFSET EQU $1A

DEF SCORE_TENS EQU $9870
DEF SCORE_ONES EQU $9871

SECTION "Header", ROM0[$100]
    nop
    jp EntryPoint

    ds $150 - @, 0 ; Make room for the header

EntryPoint:
    ; Do not turn the LCD off outside of VBlank
WaitVBlank:
    ld a, [rLY]
    cp LY_VBLANK
    jp c, WaitVBlank

    ; Turn the LCD off
    ld a, LCDC_OFF
    ld [rLCDC], a

    ; Copy the tile data
    ld de, Tiles
    ld hl, $9000
    ld bc, Tiles.end - Tiles
    call Copy

    ; Copy the tilemap
    ld de, Tilemap
    ld hl, $9800
    ld bc, Tilemap.end - Tilemap
    call Copy

    ; Copy the paddle tile
    ld de, Paddle
    ld hl, $8000
    ld bc, Paddle.end - Paddle
    call Copy

    ; Copy the ball tile
    ld de, Ball
    ld hl, $8010
    ld bc, Ball.end - Ball
    call Copy

    ; Clear OAM
    ld a, 0
    ld b, 160
    ld hl, STARTOF(OAM)
ClearOam:
    ld [hli], a
    dec b
    jp nz, ClearOam

    ; Initialize the paddle sprite in OAM
    ld hl, STARTOF(OAM)
    ld a, 128 + 16
    ld [hli], a
    ld a, 16 + 8
    ld [hli], a
    ld a, 0
    ld [hli], a
    ld [hli], a

    ; Initialize the ball sprite in OAM
    ld a, 100 + 16
    ld [hli], a
    ld a, 32 + 8
    ld [hli], a
    ld a, 1
    ld [hli], a
    ld a, 0
    ld [hli], a

    ; Initialize global variables
    ld a, 0
    ld [wFrameCounter], a
    ld [wCurKeys], a
    ld [wNewKeys], a
    ld [wScore], a

    ; Ball starts out going up and to the right
    ld a, 1
    ld [wBallMomentumX], a
    ld a, -1
    ld [wBallMomentumY], a

    call UpdateScoreBoard

    ; Turn the LCD on
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_OBJ_ON
    ld [rLCDC], a

    ; During the first (blank) frame, initialize display registers
    ld a, %11_10_01_00
    ld [rBGP], a
    ld a, %11_10_01_00
    ld [rOBP0], a

Main:
    ; Wait until it's *not* VBlank
    ld a, [rLY]
    cp LY_VBLANK
    jp nc, Main
WaitVBlank2:
    ld a, [rLY]
    cp LY_VBLANK
    jp c, WaitVBlank2

    ; Add the ball's momentum to its position in OAM
    ld a, [wBallMomentumX]
    ld b, a
    ld a, [STARTOF(OAM) + 5]
    add a, b
    ld [STARTOF(OAM) + 5], a

    ld a, [wBallMomentumY]
    ld b, a
    ld a, [STARTOF(OAM) + 4]
    add a, b
    ld [STARTOF(OAM) + 4], a

BounceOnTop:
    ; Remember OAM has an offset (8, 16) is (0, 0) on the screen
    ld a, [STARTOF(OAM) + 4]
    sub a, 16 + 1
    ld c, a
    ld a, [STARTOF(OAM) + 5]
    sub a, 8
    ld b, a
    call GetTileByPixel
    ld a, [hl]
    call IsWallTile
    jp nz, BounceOnRight
    call CheckAndHandleBrick
    ld a, 1
    ld [wBallMomentumY], a

BounceOnRight:
    ld a, [STARTOF(OAM) + 4]
    sub a, 16
    ld c, a
    ld a, [STARTOF(OAM) + 5]
    sub a, 8 - 1
    ld b, a
    call GetTileByPixel
    ld a, [hl]
    call IsWallTile
    jp nz, BounceOnLeft
    call CheckAndHandleBrick
    ld a, -1
    ld [wBallMomentumX], a

BounceOnLeft:
    ld a, [STARTOF(OAM) + 4]
    sub a, 16
    ld c, a
    ld a, [STARTOF(OAM) + 5]
    sub a, 8 + 1
    ld b, a
    call GetTileByPixel
    ld a, [hl]
    call IsWallTile
    jp nz, BounceOnBottom
    call CheckAndHandleBrick
    ld a, 1
    ld [wBallMomentumX], a

BounceOnBottom:
    ld a, [STARTOF(OAM) + 4]
    sub a, 16 - 1
    ld c, a
    ld a, [STARTOF(OAM) + 5]
    sub a, 8
    ld b, a
    call GetTileByPixel
    ld a, [hl]
    call IsWallTile
    jp nz, BounceDone
    call CheckAndHandleBrick
    ld a, -1
    ld [wBallMomentumY], a
BounceDone:

    ; First, check if the ball is low enough to bounce off the paddle.
    ld a, [STARTOF(OAM)]
    ld b, a
    ld a, [STARTOF(OAM) + 4]
    ; Adjusted to make it feel like the ball isn't sinking into the paddle
    add a, 4
    cp a, b
    ; If the ball isn't at the same Y position as the paddle, it can't bounce.
    jp nz, PaddleBounceDone

    ; Now let's compare the X positions of the objects to see if they're touching.
    ld a, [STARTOF(OAM) + 5] ; Ball's X position.
    ld b, a
    ld a, [STARTOF(OAM) + 1] ; Paddle's X position.
    sub a, 8
    cp a, b
    jp nc, PaddleBounceDone
    add a, 8 + 16 ; 8 to undo, 16 as the width.
    cp a, b
    jp c, PaddleBounceDone

    ld a, -1
    ld [wBallMomentumY], a

PaddleBounceDone:


    ; Check the current keys every frame and move left or right
    call UpdateKeys

; Check if the left button is pressed
CheckLeft:
    ld a, [wCurKeys]
    and a, PAD_LEFT
    jp z, CheckRight
Left:
    ; Move the paddle one pixel to the left
    ld a, [STARTOF(OAM) + 1]
    dec a
    ; If object hit the edge then don't move
    cp a, 15
    jp z, Main
    ld [STARTOF(OAM) + 1], a
    jp Main

; Check if right button is pressed
CheckRight:
    ld a, [wCurKeys]
    and a, PAD_RIGHT
    jp z, Main
Right:
    ; Move the paddle one pixel to the right
    ld a, [STARTOF(OAM) + 1]
    inc a
    ; If object hit the edge then don't move
    cp a, 105
    jp z, Main
    ld [STARTOF(OAM) + 1], a
    jp Main

; Copy bytes from one area to another.
; @param de: Source
; @param hl: Destination
; @param bc: Length
Copy:
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or a, c
    jp nz, Copy
    ret

UpdateKeys:
    ; Poll half the controller
    ld a, JOYP_GET_BUTTONS
    call .one_nibble
    ; B7-4 = 1; B3-0 unpressed buttons
    ld b, a

    ; Poll the other half
    ld a, JOYP_GET_CTRL_PAD
    call .one_nibble
    ; A7-4 = unpressed directions; A3-0 = 1
    swap a
    xor a, b
    ld b, a

    ; Release the controller
    ld a, JOYP_GET_NONE
    ldh [rJOYP], a

    ; Combine with previous wCurKeys to make wNewKeys
    ld a, [wCurKeys]
    xor a, b ; A = keys that changed state
    and a, b ; A = keys that changed to pressed
    ld [wNewKeys], a
    ld a, b
    ld [wCurKeys], a
    ret

.one_nibble
    ldh [rJOYP], a
    call .known_ret
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    or $F0
.known_ret
    ret

; Convert a pixel position to a tilemap address
; hl = $9800 + X + Y * 32
; @param b: X
; @param c: Y
; @return hl: tile address
GetTileByPixel:
    ; First, we need to divide by 8 to convert a pixel position to a tile position.
    ; After this we want to multiply the Y position by 32.
    ; These operations effectively cancel out so we need to mask the Y value.
    ld a, c
    and a, %11111000
    ld l, a
    ld h, 0

    ; Now we have the position * 8 in hl
    add hl, hl ; position * 16
    add hl, hl ; position * 32

    ; Convert the X position to an offset
    ld a, b
    srl a ; a / 2
    srl a ; a / 4
    srl a ; a / 8

    ; Add the two offsets together
    add a, l
    ld l, a
    adc a, h
    sub a, l
    ld h, a

    ; Add the offset to the tilemap's base address
    ld bc, $9800
    add hl, bc
    ret

; @param a: tile ID
; @return z: set if a is a wall
IsWallTile:
    cp a, $00
    ret z
    cp a, $01
    ret z
    cp a, $02
    ret z
    cp a, $03
    ret z
    cp a, $04
    ret z
    cp a, $05
    ret z
    cp a, $06
    ret z
    cp a, $07
    ret

; checks if a brick was collided with and breaks it if possible
; @param hl: address of tile
CheckAndHandleBrick:
    ld a, [hl]
    cp a, BRICK_LEFT
    jr nz, CheckAndHandleBrickRight
    ; Break a brick from the left side
    ld [hl], BLANK_TILE
    inc hl
    ld [hl], BLANK_TILE
    call IncreaseScore
CheckAndHandleBrickRight:
    cp a, BRICK_RIGHT
    ret nz
    ; Break a brick from the right side
    ld [hl], BLANK_TILE
    dec hl
    ld [hl], BLANK_TILE
    call IncreaseScore
    ret

; Increase score by 1 and store it as BCD number
; Changes a and hl
IncreaseScore:
    xor a
    inc a
    ld hl, wScore
    adc [hl]
    daa
    ld [hl], a
    call UpdateScoreBoard
    ret

; Read BCD score from wScore and updates the score display
UpdateScoreBoard:
    ld a, [wScore]
    and %11110000
    swap a
    add a, DIGIT_OFFSET
    ld [SCORE_TENS], a

    ld a, [wScore]
    and %00001111
    add a, DIGIT_OFFSET
    ld [SCORE_ONES], a
    ret

Tiles:
    dw `33333333, `33333333, `33333333, `33322222, `33322222, `33322222, `33322211, `33322211 ; $00
    dw `33333333, `33333333, `33333333, `22222222, `22222222, `22222222, `11111111, `11111111 ; $01
    dw `33333333, `33333333, `33333333, `22222333, `22222333, `22222333, `11222333, `11222333 ; $02
    dw `33333333, `33333333, `33333333, `33333333, `33333333, `33333333, `33333333, `33333333 ; $03
    dw `33322211, `33322211, `33322211, `33322211, `33322211, `33322211, `33322211, `33322211 ; $04
    dw `22222222, `20000000, `20111111, `20111111, `20111111, `20111111, `22222222, `33333333 ; $05
    dw `22222223, `00000023, `11111123, `11111123, `11111123, `11111123, `22222223, `33333333 ; $06
    dw `11222333, `11222333, `11222333, `11222333, `11222333, `11222333, `11222333, `11222333 ; $07
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000 ; $08
    dw `11001100, `11111111, `11111111, `21212121, `22222222, `22322232, `23232323, `33333333 ; $09
    dw `33000000, `33000000, `33000000, `33000000, `33111100, `33111100, `33111111, `33111111 ; $0A
    dw `33331111, `00331111, `00331111, `00331111, `00331111, `00331111, `11331111, `11331111 ; $0B
    dw `11333300, `11113300, `11113300, `11113300, `11113311, `11113311, `11113311, `11113311 ; $0C
    dw `00003333, `00000033, `00000033, `00000033, `11000033, `11000033, `11111133, `11111133 ; $0D
    dw `33111111, `33111111, `33111111, `33111111, `33111111, `33111111, `33111111, `33111111 ; $0E
    dw `11331111, `11331111, `11331111, `11331111, `11331111, `11331111, `11331111, `11331111 ; $0F
    dw `11113311, `11113311, `11113311, `11113311, `11113311, `11113311, `11113311, `11113311 ; $10
    dw `11111133, `11111133, `11111133, `11111133, `11111133, `11111133, `11111133, `11111133 ; $11
    dw `33111111, `33111111, `33111111, `33111111, `33111111, `33111111, `33111111, `33111111 ; $12
    dw `11331111, `11331111, `11331111, `11331111, `11331111, `11331111, `11331111, `11331111 ; $13
    dw `11113311, `11113311, `11113311, `11113311, `11113311, `11113311, `11113311, `11113311 ; $14
    dw `11111133, `11111133, `11111133, `11111133, `11111133, `11111133, `11111133, `11111133 ; $15
    dw `33111111, `33111111, `33111111, `33111111, `33111111, `33111111, `33111111, `33111111 ; $16
    dw `11331111, `11331111, `11331111, `11331111, `11330000, `11330000, `11330000, `33330000 ; $17
    dw `11113311, `11113311, `00003311, `00003311, `00003311, `00003311, `00003311, `00333311 ; $18
    dw `11111133, `11111133, `11111133, `11111133, `11111133, `11111133, `11111133, `11113333 ; $19

    ; digits
    ; 0
    dw `33333333
    dw `33000033
    dw `30033003
    dw `30033003
    dw `30033003
    dw `30033003
    dw `33000033
    dw `33333333
    ; 1
    dw `33333333
    dw `33300333
    dw `33000333
    dw `33300333
    dw `33300333
    dw `33300333
    dw `33000033
    dw `33333333
    ; 2
    dw `33333333
    dw `33000033
    dw `30330003
    dw `33330003
    dw `33000333
    dw `30003333
    dw `30000003
    dw `33333333
    ; 3
    dw `33333333
    dw `30000033
    dw `33330003
    dw `33000033
    dw `33330003
    dw `33330003
    dw `30000033
    dw `33333333
    ; 4
    dw `33333333
    dw `33000033
    dw `30030033
    dw `30330033
    dw `30330033
    dw `30000003
    dw `33330033
    dw `33333333
    ; 5
    dw `33333333
    dw `30000033
    dw `30033333
    dw `30000033
    dw `33330003
    dw `30330003
    dw `33000033
    dw `33333333
    ; 6
    dw `33333333
    dw `33000033
    dw `30033333
    dw `30000033
    dw `30033003
    dw `30033003
    dw `33000033
    dw `33333333
    ; 7
    dw `33333333
    dw `30000003
    dw `33333003
    dw `33330033
    dw `33300333
    dw `33000333
    dw `33000333
    dw `33333333
    ; 8
    dw `33333333
    dw `33000033
    dw `30333003
    dw `33000033
    dw `30333003
    dw `30333003
    dw `33000033
    dw `33333333
    ; 9
    dw `33333333
    dw `33000033
    dw `30330003
    dw `30330003
    dw `33000003
    dw `33330003
    dw `33000033
    dw `33333333
.end

Tilemap:
    db $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $02, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $0A, $0B, $0C, $0D, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $0E, $0F, $10, $11, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $12, $13, $14, $15, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $16, $17, $18, $19, $03, 0,0,0,0,0,0,0,0,0,0,0,0
    db $04, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
.end

Paddle:
    dw `13333331
    dw `30000003
    dw `13333331
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
.end

Ball:
    dw `00033000
    dw `00322300
    dw `03222230
    dw `03222230
    dw `00322300
    dw `00033000
    dw `00000000
    dw `00000000
.end

SECTION "Counter", WRAM0
wFrameCounter: ds 1

SECTION "Input Variables", WRAM0
wCurKeys: ds 1
wNewKeys: ds 1

SECTION "Ball Data", WRAM0
wBallMomentumX: ds 1
wBallMomentumY: ds 1

SECTION "Score", WRAM0
wScore: ds 1
