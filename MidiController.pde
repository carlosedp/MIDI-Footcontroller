#include <NewSoftSerial.h>
#include <MIDISoft.h>
#include <LedControl.h>
#include <EEPROM.h>
#include <MemoryFree.h>
#include <Flash.h>

/*
   Midi switcher controller based on CAE RS5
   by Carlos Eduardo de Paula (CarlosEDP)
http://carlosedp.tumblr.com
http://twitter.com/carlosedp

Versions:
1.0 - 2010-06
 */

#define DEBUG

// Macro to print debug statements to serial port. Can be disabled commenting the "#define DEBUG" line
#ifdef DEBUG
#define DEBUG_PRINT(x)  Serial.print(x)
#else
#define DEBUG_PRINT(x)
#endif

// Pins used on SoftSerial for MIDI Communication
#define MIDI1 2
#define MIDI2 3

// Momentary buttons wired using 2x 74HC151 multiplexer to read switches (up to 16)
// Mux control pins
#define MUXENC1 4
#define MUXENC2 5
#define MUXENC3 6
#define MUXSTROBE 7

// Mux read pins
#define MUX1 8
#define MUX2 9

// Pins to communicate to Maxim 72XX Led Driver
#define DISP1 10
#define DISP2 11
#define DISP3 12

// LED pin on Arduino board
#define LED 13

// Create a SoftSerial for the MIDI interface
NewSoftSerial SoftSer(MIDI1,MIDI2);

// Now we need a LedControl to work with.
// pin DISP1 is connected to the DataIn
// pin DISP2 is connected to the CLK
// pin DISP3 is connected to LOAD
// We have only a single MAX72XX.
LedControl Lc=LedControl(DISP1,DISP2,DISP3,1);

int ledArrayRow[] =    {3,3,3,3,3,3,3,3,4,4};
int ledArrayColumn[] = {0,1,2,3,4,5,6,7,0,1};

// Blinking interval
#define blinkInterval 500

// The display needs to blink?
boolean blinkingDisp = false;

// dispState used to set the blinking dot
int dispState = LOW;

// Store last time the dot was updated
long dispPreviousMillis = 0;

// Variables for the memory report
boolean reportMem = true;
#define memReportInterval 1000
int memPreviousMillis = 0;

// LedControl address of the blinking dot
int dotArray[] = {2,0};
// dotState used to set the blinking dot
boolean dotState = false;
// Store last time the dot was updated
long dotPreviousMillis = 0;

// Declare variables to control 2x 74HC151 MUX
int MuxVal1 = 0;
int MuxVal2 = 0;
int MuxVal3 = 0;
int BinVal = 0;
int MuxLoop = 0;

// BinPat is used for figuring out the High / Low (1/0) values of the MUX control pins
int BinPat [] = {000, 1, 10, 11, 100, 101, 110, 111};

// Buttons timing setup
#define debounce 50 // ms debounce period to prevent flickering when pressing or releasing the button
#define repeatTime 250 // ms repeat period: once the button is held, the time is reduced
#define holdTime 1500 // ms hold period: how long to wait for press+hold event

// Button port 1 variables
int button1Val = 0; // value read from button
int button1Last = 1; // buffered value of the button's previous state
long btn1DnTime; // time the button was pressed down
long btn1UpTime; // time the button was released
boolean btn1Held = false; // flag the button as held to reduce the repetition time
boolean ignore1Up = false; // whether to ignore the button release because the click+hold was triggered

// Button port 2 variables
int button2Val = 0; // value read from button
int button2Last = 1; // buffered value of the button's previous state
long btn2DnTime; // time the button was pressed down
long btn2UpTime; // time the button was released
boolean btn2Held = false; // flag the button as held to reduce the repetition time
boolean ignore2Up = false; // whether to ignore the button release because the click+hold was triggered

// MidiChannel sets the channel to be used by MIDI communication
byte MidiChannel;

// SwitchMode selects between multiple modes like Preset, Direct, Edit
// SwitchMode = 0 -> Preset Mode.
// SwitchMode = 1 -> Direct Mode.
// SwitchMode = 2 -> Transitory, while in Bank/Preset select mode.
int SwitchMode = 0;

// NBanks - Quantity of banks
#define NBanks 30

// Bank - Current bank in use.
int Bank = 0;

// TempBank - Temporary bank while preset is not choosed
int TempBank = 0;

// Preset - Current preset in use.
int Preset = 1;

// CurrentPresetControl - Holds the current controls associated  with the preset
byte CurrentPresetControl[10] = { 80, 81, 82, 83, 84, 85, 86, 87, 88, 89 };

// CurrentPresetValue - Holds the current control values associated with the preset (0 or 127)
byte CurrentPresetValue[10] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

// OrigPresetValue - Holds the original control values associated with the preset (0 or 127)
byte OrigPresetValue[10] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

// Memory address positions for various parameters
#define MidiChannelAddress 5
#define LastBankAddress 10
#define LastPresetAddress 20
#define InitialControlAddress 100
#define InitialValueAddress 500

/* -------------------------- Setup Arduino -------------------------- */
void setup() {
    // Initialize Serial port for debugging
    Serial.begin(57600);
    DEBUG_PRINT(F("----------- Start setup() sequence -----------\n"));

    // Setup MUX reader pins and activate pullup resistor
    DEBUG_PRINT(F("Setup multiplexer pins\n"));
    pinMode(MUX1, INPUT);
    digitalWrite(MUX1, HIGH);
    pinMode(MUX2, INPUT);
    digitalWrite(MUX2, HIGH);

    // Setup multiplexer pins
    pinMode(MUXENC1, OUTPUT);
    pinMode(MUXENC2, OUTPUT);
    pinMode(MUXENC3, OUTPUT);
    pinMode(MUXSTROBE, OUTPUT);

    // Setup Led Driver
    DEBUG_PRINT(F("Setup Led driver\n"));
    Lc.shutdown(0,false);  // The MAX72XX is in power-saving mode on startup, we have to do a wakeup call
    Lc.setIntensity(0,8);  // Set the brightness to a medium values
    Lc.clearDisplay(0);    // Clear the display

    // Set the arduino Led pin mode
    pinMode(LED, OUTPUT);

    // Load MIDI channel. MidiChannel = 0 is omni mode.
    MidiChannel = EEPROM.read(MidiChannelAddress);
    if (MidiChannel > 16) {
        MidiChannel = 0;
        DEBUG_PRINT(F("Loaded from EEPROM MIDI Channel n. "));
        DEBUG_PRINT((int)MidiChannel);
        DEBUG_PRINT(F("\n"));
    }

    // Create a SoftSerial to use on MIDI communication
    DEBUG_PRINT(F("Create SoftSerial and MIDI interface\n"));
    // Set SoftSerial port speed
    SoftSer.begin(31250);
    // Initialize MIDI
    MIDI.begin(SoftSer, MidiChannel);

    // Load last used bank
    Bank = EEPROMReadInt(LastBankAddress);
    if (Bank > NBanks) {
        Bank = 0;
    }
    TempBank = Bank;
    DEBUG_PRINT(F("Loaded from EEPROM Bank n. "));
    DEBUG_PRINT(Bank);
    DEBUG_PRINT(F("\n"));

    // Load last used preset from memory
    Preset = EEPROMReadInt(LastPresetAddress);
    if (Preset < 1 && Preset > 5) {
        Preset = 1;
    }
    DEBUG_PRINT(F("Loaded from EEPROM last used preset n. "));
    DEBUG_PRINT(Preset);
    DEBUG_PRINT(F("\n"));

    // Switch to start mode
    changeMode(SwitchMode);

    // Load preset for current bank from EEPROM
    loadPreset();

    DEBUG_PRINT(F("----------- End of setup() sequence -----------\n"));

    SwitchPressed(12);  //<------------------ REMOVE
}

/* -------------------------- Start Arduino Main Loop -------------------------- */
void loop() {
    /* <------------------ REMOVE

       for (MuxLoop = 0 ; MuxLoop <= 7 ; MuxLoop++) {
       BinVal = BinPat[MuxLoop];
       MuxVal1 = BinVal & 0x01;
       MuxVal2 = (BinVal>>1) & 0x01;
       MuxVal3 = (BinVal>>2) & 0x01;
       digitalWrite(MUXENC1, MuxVal1);
       digitalWrite(MUXENC2, MuxVal2);
       digitalWrite(MUXENC3, MuxVal3);

     */// <------------------ REMOVE
    // Strobe LOW to read
    digitalWrite(MUXSTROBE,LOW);

    int Bt1 = 1;  // <------------------ REMOVE
    int Bt2 = 10;  // <------------------ REMOVE

    // Read the state of the button 1
    button1Val = digitalRead(MUX1);

    // Test for button pressed and store the down time
    if (button1Val == LOW && button1Last == HIGH && (millis() - btn1UpTime) > long(debounce)) {
        btn1DnTime = millis();
        btn1Held = false; //TODO - NEWCODE-TEST
    }

    // Test for button release and store the up time
    if (button1Val == HIGH && button1Last == LOW && (millis() - btn1DnTime) > long(debounce)) {
        if (ignore1Up == false) {
            //SwitchPressed(MuxLoop*2); //<------------------ UNCOMMENT
            SwitchPressed(Bt1);  //<------------------ REMOVE
        } else {
            ignore1Up = false;
        }
        btn1UpTime = millis();
    }

    // Test for button held down for longer than the hold time - start repeats
    if (button1Val == LOW && btn1Held == true && (millis() - btn1DnTime) > long(repeatTime)) {   //TODO - NEWCODE-TEST
        //SwitchHold(MuxLoop*2); //<------------------ UNCOMMENT
        SwitchHold(Bt1);  //<------------------ REMOVE
        ignore1Up = true;
        btn1DnTime = millis();
    }   //TODO - NEWCODE-TEST

    // Test for button held down for longer than the hold time
    if (button1Val == LOW && btn1Held == false && (millis() - btn1DnTime) > long(holdTime)) {
        //SwitchHold(MuxLoop*2); //<------------------ UNCOMMENT
        SwitchHold(Bt1);  //<------------------ REMOVE
        ignore1Up = true;
        btn1DnTime = millis();
        btn1Held = true;  //TODO - NEWCODE-TEST
    }
    button1Last = button1Val;

    // Read the state of the button 2
    button2Val = digitalRead(MUX2);

    // Test for button pressed and store the down time
    if (button2Val == LOW && button2Last == HIGH && (millis() - btn2UpTime) > long(debounce)) {
        btn2DnTime = millis();
        btn2Held = false;  //TODO - NEWCODE-TEST
    }

    // Test for button release and store the up time
    if (button2Val == HIGH && button2Last == LOW && (millis() - btn2DnTime) > long(debounce)) {
        if (ignore2Up == false) {
            //SwitchPressed(MuxLoop*2+1); //<------------------ UNCOMMENT
            SwitchPressed(Bt2);  //<------------------ REMOVE
        } else {
            ignore2Up = false;
        }
        btn2UpTime = millis();
    }

    // Test for button held down for longer than the hold time - start repeats
    if (button2Val == LOW && btn2Held == true && (millis() - btn2DnTime) > long(repeatTime)) {   //TODO - NEWCODE-TEST
        //SwitchHold(MuxLoop*2+1); //<------------------ UNCOMMENT
        SwitchHold(Bt2);  //<------------------ REMOVE
        ignore2Up = true;
        btn2DnTime = millis();
    }   //TODO - NEWCODE-TEST

    // Test for button held down for longer than the hold time
    if (button2Val == LOW && btn2Held == false && (millis() - btn2DnTime) > long(holdTime)) {
        //SwitchHold(MuxLoop*2+1); //<------------------ UNCOMMENT
        SwitchHold(Bt2);  //<------------------ REMOVE
        ignore2Up = true;
        btn2DnTime = millis();
        btn2Held = true;  //TODO - NEWCODE-TEST
    }
    button2Last = button2Val;

    // Strobe HIGH to avoid jitters
    digitalWrite(MUXSTROBE,HIGH);
    // }  // End for  <------------------ REMOVE

    // Call the background manager function
    backgroundMGR();
}  /* -------------------------- End Arduino Main Loop -------------------------- */

/* This function is triggered when the user press a button */
void SwitchPressed(int sw) {
    // Behaviour for 0 - 9
    if (sw >= 0 && sw <= 9) {
        if (SwitchMode == 1) {
            // Switches in direct mode
            DEBUG_PRINT(F("SwitchPressed - "));
            DEBUG_PRINT (sw);
            DEBUG_PRINT(F(" - Switch in Direct Mode\n"));
            DirectModeSwitcher(sw);
        } else if (SwitchMode == 0) {
            // Switches in Preset mode
            DEBUG_PRINT(F("SwitchPressed - "));
            DEBUG_PRINT (sw);
            DEBUG_PRINT(F(" - Switch in Preset Mode\n"));
            if (sw >= 1 && sw <= 5) {
                DirectModeSwitcher(sw);
            } else {
                PresetModeSwitcher(sw);
            }
        } else if (SwitchMode == 2) {
            // Switches in temporary bank selection
            DEBUG_PRINT(F("SwitchPressed - "));
            DEBUG_PRINT (sw);
            DEBUG_PRINT(F(" - Switch in Bank Select Mode\n"));
            if (sw >= 1 && sw <= 5) {
                DirectModeSwitcher(sw);
            } else {
                // Commit TempBank -> Bank
                Bank = TempBank;
                // Save selected bank into Last Used Bank memory address
                EEPROMWriteInt(LastBankAddress, Bank);
                // Load selected Preset for the new Bank
                blinkingDisp = false;
                PresetModeSwitcher(sw);
                // Return to Preset Mode
                changeMode(0);
            }
        }
    }
    // Behaviour for Up
    if (sw == 10) {
        if (SwitchMode == 1) {
            // In direct mode
            DEBUG_PRINT (F("SwitchPressed - Switch Up - In Direct Mode\n"));
            // Undo current switch state and reload preset
            loadPreset();
        } else if (SwitchMode == 0) {
            // In Preset Mode
            DEBUG_PRINT (F("SwitchPressed - Switch Up - In Preset Mode\n"));
            bankUp();
        } else if (SwitchMode == 2) {
            // In Temp Bank Mode
            DEBUG_PRINT (F("SwitchPressed - Switch Up - In Temp Bank Mode\n"));
            bankUp();
        }
    }
    // Behaviour for Down
    if (sw == 11) {
        if (SwitchMode == 1) {
            DEBUG_PRINT (F("SwitchPressed - Switch Down - In Direct Mode\n"));
            // In direct mode
            // Save current switch state into preset
            savePreset();
        } else if (SwitchMode == 0) {
            // In Preset Mode
            DEBUG_PRINT (F("SwitchPressed - Switch Down - In Preset Mode\n"));
            bankDown();
        } else if (SwitchMode == 2) {
            DEBUG_PRINT (F("SwitchPressed - Switch Down - In Temp Bank Mode\n"));
            bankDown();
        }
    }
    // Behaviour for Dir/Edit
    if (sw == 12) {
        if (SwitchMode == 1) {
            DEBUG_PRINT (F("SwitchPressed - Dir/Edit - Switching to Preset Mode\n"));
            changeMode(0);
        } else if (SwitchMode == 0) {
            DEBUG_PRINT (F("SwitchPressed - Dir/Edit - Switching to Direct Mode\n"));
            changeMode(1);
        } else if (SwitchMode == 2) {
            DEBUG_PRINT(F("SwitchPressed - Dir/Edit - Switch in temporary bank select mode\n"));
            // Undo bank selection mode
            TempBank = Bank;
            // Make display stop blinking
            blinkingDisp = false;
            // Return to Preset Mode
            changeMode(0);
            // Update display to show current bank
            updateDisplay();
            // Update leds to show current preset and direct switches
            updateLeds();
        }
    }
    // Buttons 13, 14, 15 not used
}

/* This function is triggered when the user holds a button pressed */
void SwitchHold(int sw) {
    // Behaviour for Up
    if (sw == 10) {
        if (SwitchMode == 1) {
            // In direct mode
            DEBUG_PRINT (F("SwitchPressed - Switch Up - In Direct Mode\n"));
            // Undo current switch state and reload preset
            loadPreset();
        } else if (SwitchMode == 0) {
            // In Preset Mode
            DEBUG_PRINT (F("SwitchPressed - Switch Up - In Preset Mode\n"));
            bankUp();
        } else if (SwitchMode == 2) {
            DEBUG_PRINT (F("SwitchPressed - Switch Up - In Temp Bank Mode\n"));
            bankUp();
        }
    }
    // Behaviour for Down
    if (sw == 11) {
        if (SwitchMode == 1) {
            DEBUG_PRINT (F("SwitchPressed - Switch Down - In Direct Mode\n"));
            // In direct mode
            // Save current switch state into preset
            savePreset();
        } else if (SwitchMode == 0) {
            // In Preset Mode
            DEBUG_PRINT (F("SwitchPressed - Switch Down - In Preset Mode\n"));
            bankDown();
        } else if (SwitchMode == 2) {
            DEBUG_PRINT (F("SwitchPressed - Switch Down - In Temp Bank Mode\n"));
            bankDown();
        }
    }
}

/* Manages the button behaviour on Direct Mode */
void PresetModeSwitcher(int sw) {
    // Preset-switch mapping
    // Switches 6 7 8 9 0
    //          | | | | |
    // Presets  1 2 3 4 5
    switch(sw) {
        case 6:
            Preset = 1;
            break;
        case 7:
            Preset = 2;
            break;
        case 8:
            Preset = 3;
            break;
        case 9:
            Preset = 4;
            break;
        case 0:
            Preset = 5;
            break;
    }
    // Load preset from memory
    loadPreset();

    // Save last used preset into EEPROM
    EEPROMWriteInt(LastPresetAddress, Preset);

    // Update Leds
    updateLeds();

    // Update Display
    updateDisplay();
}

/* Manages the button behaviour on Direct Mode */
void DirectModeSwitcher(int sw) {
    // Read value from current bank
    byte SwitchState = CurrentPresetValue[sw];
    if ( SwitchState == 0 ) {
        CurrentPresetValue[sw] =  127;
    } else if ( SwitchState == 127 ) {
        CurrentPresetValue[sw] =  0;
    }

    DEBUG_PRINT(F("DirectModeSwitcher - Sending control "));
    DEBUG_PRINT((int)CurrentPresetControl[sw]);
    DEBUG_PRINT(F(" value "));
    DEBUG_PRINT((int)CurrentPresetValue[sw]);
    DEBUG_PRINT("\n");
    // Send new value
    sendMidiCC(CurrentPresetControl[sw], CurrentPresetValue[sw]);

    // Update Leds
    updateLeds();
}

/* Changes current mode and does all updates do leds/display */
void changeMode(int mode) {
    DEBUG_PRINT(F("changeMode - Changing mode to  "));
    DEBUG_PRINT(mode);
    DEBUG_PRINT(F("\n"));
    SwitchMode = mode;
    updateDisplay();
    updateLeds();
}

/* Bank up function */
void bankUp() {
    // Change mode to temporary bank select
    if (SwitchMode != 2) {
        changeMode(2);
        blinkingDisp = true;
    }
    // Increase the temporary bank
    TempBank = TempBank + 1;
    if (TempBank >= NBanks) {
        TempBank = 0;
    }
    // Display temporary bank in display
    updateDisplay();
}

/* Bank down function */
void bankDown() {
    // Change mode to temporary bank select
    if (SwitchMode != 2) {
        changeMode(2);
        blinkingDisp = true;
    }
    // Decrease the temporary bank
    TempBank = TempBank - 1;
    if (TempBank < 0) {
        TempBank = NBanks-1;
    }
    // Display temporary bank in display
    updateDisplay();
}

/* Loads the selected preset from memory setting the controls and values */
void loadPreset() {
    // Load control numbers from EEPROM. If none defined, start with 80 - 89.
    DEBUG_PRINT(F("loadPreset - Loaded control numbers {"));
    byte defaultControl = 80;
    for (int N=0 ; N < 10 ; N++) {
        byte value = EEPROM.read((Bank*10) + ((Preset-1)*10) + InitialControlAddress + N);
        if (value >=0 && value <= 119) {
            CurrentPresetControl[N] = value;
        } else {
            CurrentPresetControl[N] = defaultControl+N;
        }
        DEBUG_PRINT((int)CurrentPresetControl[N]);
        DEBUG_PRINT(F(","));
    }
    DEBUG_PRINT(F("}\n"));

    // Load control values from EEPROM. If none defined, set as 0.
    DEBUG_PRINT(F("loadPreset - Loaded control values {"));
    byte defaultValue = 0;
    for (int N=0 ; N < 10 ; N++) {
        byte value = EEPROM.read((Bank*10) + ((Preset-1)*10) + InitialValueAddress + N);
        if (value == 0 || value == 127) {
            CurrentPresetValue[N] = value;
        } else {
            CurrentPresetValue[N] = defaultValue;
        }
        DEBUG_PRINT((int)CurrentPresetValue[N]);
        DEBUG_PRINT(F(","));
    }
    DEBUG_PRINT(F("}\n"));

    memcpy(OrigPresetValue, CurrentPresetValue, 10);

    DEBUG_PRINT("Loaded preset ");
    DEBUG_PRINT(Preset);
    DEBUG_PRINT(" for bank ");
    DEBUG_PRINT(Bank);
    DEBUG_PRINT("\n");

    sendPresetSwitches();
}

/* Saves the current switch values to actual preset (last selected) */
void savePreset() {
    DEBUG_PRINT(F("savePreset - Saving control values for bank "));
    DEBUG_PRINT(Bank);
    DEBUG_PRINT(F(" preset "));
    DEBUG_PRINT(Preset);
    DEBUG_PRINT(F(" into EEPROM.\n"));
    for (int N=0 ; N < 10 ; N++) {
        EEPROM.write((Bank*10) + ((Preset-1)*10) + InitialValueAddress + N, CurrentPresetValue[N]);
    }
    // Make both variables the same so the dot stops blinking
    memcpy(OrigPresetValue, CurrentPresetValue, 10);
}

/* Sends all control and value MIDI commands for the current preset */
void sendPresetSwitches() {
    DEBUG_PRINT(F("sendPresetSwitches - Sending all switch control and values for bank "));
    DEBUG_PRINT(Bank);
    DEBUG_PRINT(F(" preset "));
    DEBUG_PRINT(Preset);
    DEBUG_PRINT(F("\n"));
    for (int N = 0 ; N <= 9 ; N++) {
        sendMidiCC(CurrentPresetControl[N], CurrentPresetValue[N]);
    }
}

/* Sends the message via MIDI interface */
void sendMidiCC(byte ControlNumber, byte ControlValue) {
    DEBUG_PRINT(F("sendMidiCC - Sending MIDI control "));
    DEBUG_PRINT(int(ControlNumber));
    DEBUG_PRINT(F(", Value "));
    DEBUG_PRINT(int(ControlValue));
    DEBUG_PRINT(F(" on channel "));
    DEBUG_PRINT(int(MidiChannel));
    DEBUG_PRINT("\n");
    MIDI.sendControlChange(ControlNumber, ControlValue, MidiChannel);
}

/* Updates the Led states */
void updateLeds() {
    if (SwitchMode == 1) {
        DEBUG_PRINT(F("updateLeds - Updating Leds for Direct Mode\n"));
        DEBUG_PRINT(F("updateLeds - Led |"));
        for (int N = 0 ; N <= 9 ; N++) {
            if (CurrentPresetValue[N] == 127) {
                DEBUG_PRINT(N);
                DEBUG_PRINT(F(" - on|"));
                switchLed(N, true);
            } else if (CurrentPresetValue[N] == 0) {
                DEBUG_PRINT(N);
                DEBUG_PRINT(F(" - off|"));
                switchLed(N, false);
            }
        }
        DEBUG_PRINT(F("\n"));
    } else if (SwitchMode == 0) {
        DEBUG_PRINT(F("updateLeds - Updating Leds for Preset Mode\n"));
        DEBUG_PRINT(F("updateLeds - Switch Led |"));
        // Update leds for Direct switches
        for (int N = 1 ; N <= 5 ; N++) {
            if (CurrentPresetValue[N] == 127) {
                DEBUG_PRINT(N);
                DEBUG_PRINT(F(" - on|"));
                switchLed(N, true);
            } else if (CurrentPresetValue[N] == 0) {
                DEBUG_PRINT(N);
                DEBUG_PRINT(F(" - off|"));
                switchLed(N, false);
            }
        }
        // Update leds for Preset switches
        switchLed(6, false);
        switchLed(7, false);
        switchLed(8, false);
        switchLed(9, false);
        switchLed(0, false);
        DEBUG_PRINT(F(" .\nPreset Led |"));
        DEBUG_PRINT(Preset);
        DEBUG_PRINT(F(" - on.\n"));
        switch(Preset) {
            case 1:
                switchLed(6, true);
                break;
            case 2:
                switchLed(7, true);
                break;
            case 3:
                switchLed(8, true);
                break;
            case 4:
                switchLed(9, true);
                break;
            case 5:
                switchLed(0, true);
                break;
        }
    } else if (SwitchMode == 2) {
        DEBUG_PRINT(F("updateLeds - Updating Leds for temporary Bank select mode\n"));
        DEBUG_PRINT(F("updateLeds - Switch Led |"));
        // Update leds for Direct switches
        for (int N = 1 ; N <= 5 ; N++) {
            if (CurrentPresetValue[N] == 127) {
                switchLed(N, true);
                DEBUG_PRINT(N);
                DEBUG_PRINT(F(" - on|"));
            } else if (CurrentPresetValue[N] == 0) {
                switchLed(N, false);
                DEBUG_PRINT(N);
                DEBUG_PRINT(F(" - off|"));
            }
        }
        DEBUG_PRINT(F("\n"));
        // Update leds for Preset switches
        switchLed(6, false);
        switchLed(7, false);
        switchLed(8, false);
        switchLed(9, false);
        switchLed(0, false);
    }
}

/* Switches the Led state individually */
void switchLed(int led, boolean state) {
    Lc.setLed(0, ledArrayRow[led], ledArrayColumn[led], state);
}

/* Called every loop to check if the any light needs to blink */
void backgroundMGR() {
    unsigned long currentMillis = millis();

    // Check if the dot must blink. The check is made against both preset arrays.
    // If both are the same, no changes are made. If they are different, there is a change.
    if (memcmp(OrigPresetValue,CurrentPresetValue,10) != 0) {
        // Check to see if it's time to blink the LED; that is, if the
        // difference between the current time and last time you blinked
        // the LED is bigger than the interval at which you want to
        // blink the LED.
        if (currentMillis - dotPreviousMillis > blinkInterval) {
            // Save the last time you blinked the LED
            dotPreviousMillis = currentMillis;

            // If the LED is off turn it on and vice-versa:
            if (dotState == false) {
                dotState = true;
                DEBUG_PRINT(F("backgroundMGR - Dot Blink\n"));
            } else {
                dotState = false;
            }
            // Set the dot with the ledState of the variable:
            Lc.setLed(0, dotArray[0], dotArray[1], dotState);
        }
    }

    // Check if the display must blink. The check is made against blinkingDisp boolean variable
    if (blinkingDisp == true) {
        if (currentMillis - dispPreviousMillis > blinkInterval) {
            // Save the last time you blinked the display
            dispPreviousMillis = currentMillis;

            // If the display is off turn it on and vice-versa:
            if (dispState == LOW) {
                dispState = HIGH;
                printNumber(TempBank);
                DEBUG_PRINT(F("backgroundMGR - Display blink n. "));
                DEBUG_PRINT(TempBank);
                DEBUG_PRINT(F("\n"));
            } else {
                dispState = LOW;
                Lc.setRow(0,0,0);
                Lc.setRow(0,0,0);
                Lc.setRow(0,0,0);
            }
        }
    }
    // Check if the memory must be reported
    if (reportMem == true) {
        if (currentMillis - memPreviousMillis > memReportInterval) {
            // Save the last time you blinked the display
            memPreviousMillis = currentMillis;
            // Print memory usage:
            Serial.print(F("freeMemory() reports: "));
            Serial.print(freeMemory());
            Serial.print(F(" bytes free.\n"));
        }
    }
}

/* Updates the display state */
void updateDisplay() {
    if (SwitchMode == 0) {
        // In Preset Mode - Print Bank number
        DEBUG_PRINT(F("updateDisplay - Updating display for Preset Mode. Bank n. "));
        DEBUG_PRINT(Bank);
        DEBUG_PRINT("\n");
        printNumber(Bank);
    } else if (SwitchMode == 1) {
        // In Direct Mode - Print 'Dir'
        DEBUG_PRINT(F("updateDisplay - Updating display for Direct Mode.\n"));
        Lc.setChar(0,0,'D',false); //D
        Lc.setRow(0,1,B00010000);  //i
        Lc.setRow(0,2,0x05);       //r
    } else if (SwitchMode == 2) {
        // In Temp Bank select Mode - Print temporary Bank number
        DEBUG_PRINT(F("updateDisplay - Updating display for Temp Preset Mode. Bank n. "));
        DEBUG_PRINT(TempBank);
        DEBUG_PRINT("\n");
        printNumber(TempBank);
    }
}

/* Print the int to the display */
void printNumber(int v) {
    int ones;
    int tens;

    if(v < 0 || v > 99)
        return;
    ones=v%10;
    v=v/10;
    tens=v%10;
    // Now print the number digit by digit
    Lc.setDigit(0,0,(byte)tens,false);
    Lc.setDigit(0,1,(byte)ones,false);
}

/* This function will write a integer to the eeprom at the specified address */
void EEPROMWriteInt(int p_address, int p_value) {
    byte lowByte = ((p_value >> 0) & 0xFF);
    //byte highByte = ((p_value >> 8) & 0xFF);
    EEPROM.write(p_address, lowByte);
    //EEPROM.write(p_address + 1, highByte);
}

/* This function will read a integer from the eeprom at the specified address */
unsigned int EEPROMReadInt(int p_address) {
    byte lowByte = EEPROM.read(p_address);
    //byte highByte = EEPROM.read(p_address + 1);
    return(lowByte << 0) & 0xFF;
    //return ((lowByte << 0) & 0xFF) + ((highByte << 8) & 0xFF00);
}
