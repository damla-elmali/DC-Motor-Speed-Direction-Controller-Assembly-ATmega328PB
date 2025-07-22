.INCLUDE "m328PBdef.inc"

.DEF rtemp    = R16
.DEF rcount   = R17
.DEF rspeed   = R18
.DEF rstate   = R19
.DEF rdir     = R20

.equ BTN_START = 0
.equ BTN_DIR   = 1
.equ BTN_UP    = 2
.equ BTN_DOWN  = 3

.equ IN1 = 4
.equ IN2 = 5
.equ ENA = 6

.DSEG
MotorState:     .BYTE 1
DirectionState: .BYTE 1
CurrentSpeed:   .BYTE 1
ButtonPressed:  .BYTE 1

.CSEG
.ORG 0x0000
    RJMP INIT

INIT:
    ; Stack ayar�
    LDI rtemp, HIGH(RAMEND)
    OUT SPH, rtemp
    LDI rtemp, LOW(RAMEND)
    OUT SPL, rtemp

    ; Butonlar (PC0-PC3) giri� + pull-up
    LDI rtemp, 0x00
    OUT DDRC, rtemp
    LDI rtemp, 0x0F
    OUT PORTC, rtemp

    ; Motor ��k��lar� (PD4-PD6)
    LDI rtemp, (1<<IN1)|(1<<IN2)|(1<<ENA)
    OUT DDRD, rtemp

    ; LED ��k��lar� (PB0-PB3)
    LDI rtemp, 0x0F
    OUT DDRB, rtemp

    ; Timer0 Fast PWM ayar�
    LDI rtemp, (1<<WGM00)|(1<<WGM01)|(1<<COM0A1)
    OUT TCCR0A, rtemp
    LDI rtemp, (1<<CS01)    ; Prescaler = 8
    OUT TCCR0B, rtemp

    ; Ba�lang�� de�erleri
    LDI rtemp, 1
    STS CurrentSpeed, rtemp
    LDI rtemp, 0
    STS MotorState, rtemp
    STS DirectionState, rtemp
    STS ButtonPressed, rtemp
    OUT OCR0A, rtemp
    OUT PORTB, rtemp

    ; Motor pinlerini ba�lang��ta s�f�rla
    CBI PORTD, IN1
    CBI PORTD, IN2

MAIN:
    RCALL CHECK_BUTTONS
    RJMP MAIN

CHECK_BUTTONS:
    ; Buton durumlar�n� kontrol et
    IN rtemp, PINC
    ANDI rtemp, 0x0F
    CPI rtemp, 0x0F    ; Hi�bir butona bas�lm�yorsa
    BREQ NO_BUTTON_PRESSED
    
    ; Buton bas�l�, daha �nce bas�lm�� m� kontrol et
    LDS rstate, ButtonPressed
    CPI rstate, 1
    BREQ BUTTON_ALREADY_PRESSED
    
    ; Yeni buton basmas�
    LDI rstate, 1
    STS ButtonPressed, rstate
    
    ; Hangi buton oldu�unu kontrol et
    SBIS PINC, BTN_START
    RCALL TOGGLE_MOTOR
    
    SBIS PINC, BTN_DIR
    RCALL TOGGLE_DIRECTION
    
    SBIS PINC, BTN_UP
    RCALL INCREASE_SPEED
    
    SBIS PINC, BTN_DOWN
    RCALL DECREASE_SPEED
    
    RCALL DEBOUNCE_DELAY
    RET

NO_BUTTON_PRESSED:
    ; Buton b�rak�ld�
    LDI rtemp, 0
    STS ButtonPressed, rtemp
    RET

BUTTON_ALREADY_PRESSED:
    RET

TOGGLE_MOTOR:
    LDS rstate, MotorState
    LDI rtemp, 1
    EOR rstate, rtemp
    STS MotorState, rstate
    
    CPI rstate, 1
    BREQ START_THE_MOTOR
    
    ; Stop motor
    LDI rtemp, 0
    OUT OCR0A, rtemp
    OUT PORTB, rtemp
    RET

START_THE_MOTOR:
    ; H�z� 1'den ba�lat ve LED'leri g�ncelle
    LDI rtemp, 1
    STS CurrentSpeed, rtemp
    RCALL UPDATE_LEDS
    
    ; PWM de�erini ayarla (1 -> 25)
    LDI rtemp, 25
    OUT OCR0A, rtemp
    
    ; Y�n� ayarla
    LDS rstate, DirectionState
    CPI rstate, 1
    BREQ SET_REVERSE_DIR
    
    ; Forward
    SBI PORTD, IN1
    CBI PORTD, IN2
    RET

SET_REVERSE_DIR:
    ; Reverse
    CBI PORTD, IN1
    SBI PORTD, IN2
    RET

TOGGLE_DIRECTION:
    ; Sadece motor �al���rken y�n de�i�tir
    LDS rtemp, MotorState
    CPI rtemp, 1
    BRNE DIR_RET
    
    LDS rstate, DirectionState
    LDI rtemp, 1
    EOR rstate, rtemp
    STS DirectionState, rstate
    
    CPI rstate, 1
    BREQ SET_REVERSE
    
    ; Forward
    SBI PORTD, IN1
    CBI PORTD, IN2
    RET

SET_REVERSE:
    ; Reverse
    CBI PORTD, IN1
    SBI PORTD, IN2
DIR_RET:
    RET

INCREASE_SPEED:
    ; Sadece motor �al���rken h�z art�r
    LDS rtemp, MotorState
    CPI rtemp, 1
    BRNE SPEED_RET
    
    LDS rtemp, CurrentSpeed
    CPI rtemp, 15
    BRSH SPEED_RET
    
    INC rtemp
    STS CurrentSpeed, rtemp
    RCALL UPDATE_LEDS
    
    ; Lineer PWM de�eri (1-15 -> 25-255)
    ; PWM = (Speed * 16) + 9
    MOV rspeed, rtemp
    LDI rtemp, 16
    MUL rspeed, rtemp
    MOV rtemp, R0
    SUBI rtemp, -9
    OUT OCR0A, rtemp
    RET

DECREASE_SPEED:
    ; Sadece motor �al���rken h�z azalt
    LDS rtemp, MotorState
    CPI rtemp, 1
    BRNE SPEED_RET
    
    LDS rtemp, CurrentSpeed
    CPI rtemp, 2
    BRLO SPEED_RET
    
    DEC rtemp
    STS CurrentSpeed, rtemp
    RCALL UPDATE_LEDS
    
    ; Lineer PWM de�eri
    MOV rspeed, rtemp
    LDI rtemp, 16
    MUL rspeed, rtemp
    MOV rtemp, R0
    SUBI rtemp, -9
    OUT OCR0A, rtemp
SPEED_RET:
    RET

UPDATE_LEDS:
    LDS rtemp, CurrentSpeed
    ; H�z de�erini maskeyle s�n�rla (0-15)
    ANDI rtemp, 0x0F
    ; Binary LED g�sterimi i�in (PB0 = LSB, PB3 = MSB)
    OUT PORTB, rtemp
    RET

DEBOUNCE_DELAY:
    ; Yakla��k 20ms gecikme
    LDI rcount, 200
DB_LOOP1:
    LDI rtemp, 0xFF
DB_LOOP2:
    DEC rtemp
    BRNE DB_LOOP2
    DEC rcount
    BRNE DB_LOOP1
    RET