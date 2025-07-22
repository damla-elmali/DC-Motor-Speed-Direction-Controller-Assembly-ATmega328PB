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
    ; Stack ayarý
    LDI rtemp, HIGH(RAMEND)
    OUT SPH, rtemp
    LDI rtemp, LOW(RAMEND)
    OUT SPL, rtemp

    ; Butonlar (PC0-PC3) giriþ + pull-up
    LDI rtemp, 0x00
    OUT DDRC, rtemp
    LDI rtemp, 0x0F
    OUT PORTC, rtemp

    ; Motor çýkýþlarý (PD4-PD6)
    LDI rtemp, (1<<IN1)|(1<<IN2)|(1<<ENA)
    OUT DDRD, rtemp

    ; LED çýkýþlarý (PB0-PB3)
    LDI rtemp, 0x0F
    OUT DDRB, rtemp

    ; Timer0 Fast PWM ayarý
    LDI rtemp, (1<<WGM00)|(1<<WGM01)|(1<<COM0A1)
    OUT TCCR0A, rtemp
    LDI rtemp, (1<<CS01)    ; Prescaler = 8
    OUT TCCR0B, rtemp

    ; Baþlangýç deðerleri
    LDI rtemp, 1
    STS CurrentSpeed, rtemp
    LDI rtemp, 0
    STS MotorState, rtemp
    STS DirectionState, rtemp
    STS ButtonPressed, rtemp
    OUT OCR0A, rtemp
    OUT PORTB, rtemp

    ; Motor pinlerini baþlangýçta sýfýrla
    CBI PORTD, IN1
    CBI PORTD, IN2

MAIN:
    RCALL CHECK_BUTTONS
    RJMP MAIN

CHECK_BUTTONS:
    ; Buton durumlarýný kontrol et
    IN rtemp, PINC
    ANDI rtemp, 0x0F
    CPI rtemp, 0x0F    ; Hiçbir butona basýlmýyorsa
    BREQ NO_BUTTON_PRESSED
    
    ; Buton basýlý, daha önce basýlmýþ mý kontrol et
    LDS rstate, ButtonPressed
    CPI rstate, 1
    BREQ BUTTON_ALREADY_PRESSED
    
    ; Yeni buton basmasý
    LDI rstate, 1
    STS ButtonPressed, rstate
    
    ; Hangi buton olduðunu kontrol et
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
    ; Buton býrakýldý
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
    ; Hýzý 1'den baþlat ve LED'leri güncelle
    LDI rtemp, 1
    STS CurrentSpeed, rtemp
    RCALL UPDATE_LEDS
    
    ; PWM deðerini ayarla (1 -> 25)
    LDI rtemp, 25
    OUT OCR0A, rtemp
    
    ; Yönü ayarla
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
    ; Sadece motor çalýþýrken yön deðiþtir
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
    ; Sadece motor çalýþýrken hýz artýr
    LDS rtemp, MotorState
    CPI rtemp, 1
    BRNE SPEED_RET
    
    LDS rtemp, CurrentSpeed
    CPI rtemp, 15
    BRSH SPEED_RET
    
    INC rtemp
    STS CurrentSpeed, rtemp
    RCALL UPDATE_LEDS
    
    ; Lineer PWM deðeri (1-15 -> 25-255)
    ; PWM = (Speed * 16) + 9
    MOV rspeed, rtemp
    LDI rtemp, 16
    MUL rspeed, rtemp
    MOV rtemp, R0
    SUBI rtemp, -9
    OUT OCR0A, rtemp
    RET

DECREASE_SPEED:
    ; Sadece motor çalýþýrken hýz azalt
    LDS rtemp, MotorState
    CPI rtemp, 1
    BRNE SPEED_RET
    
    LDS rtemp, CurrentSpeed
    CPI rtemp, 2
    BRLO SPEED_RET
    
    DEC rtemp
    STS CurrentSpeed, rtemp
    RCALL UPDATE_LEDS
    
    ; Lineer PWM deðeri
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
    ; Hýz deðerini maskeyle sýnýrla (0-15)
    ANDI rtemp, 0x0F
    ; Binary LED gösterimi için (PB0 = LSB, PB3 = MSB)
    OUT PORTB, rtemp
    RET

DEBOUNCE_DELAY:
    ; Yaklaþýk 20ms gecikme
    LDI rcount, 200
DB_LOOP1:
    LDI rtemp, 0xFF
DB_LOOP2:
    DEC rtemp
    BRNE DB_LOOP2
    DEC rcount
    BRNE DB_LOOP1
    RET