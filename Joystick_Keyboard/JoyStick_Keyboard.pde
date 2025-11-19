import java.awt.Robot;
import java.awt.event.KeyEvent;
import processing.serial.*;

Robot bot;
Serial myPort;

int SERIAL_PORT_INDEX = -1;

// Toggle control
boolean inputEnabled = false;
int btnX = 20, btnY = 20, btnW = 200, btnH = 50;

// Key state trackers
boolean enterDown = false;
boolean spaceDown = false;
boolean wDown = false;
boolean aDown = false;
boolean sDown = false;
boolean dDown = false;

// Sensor values
int FSRValue = 0;
int FlexValue = 0;
int joyX = 0;
int joyY = 0;
int buttonState = 0;

void setup() {
  size(450, 260);

  try {
    bot = new Robot();
  }
  catch (Exception e) {
    println("Robot init error: " + e);
  }

  setupSerial();
}

void draw() {
  background(20);
  // ----------------------------
  // DRAW TOGGLE BUTTON
  // ----------------------------
  if (inputEnabled) {
    fill(0, 200, 0);
  } else {
    fill(200, 0, 0);
  }
  rect(btnX, btnY, btnW, btnH, 10);

  fill(255);
  textSize(20);
  textAlign(CENTER, CENTER);
  text(inputEnabled ? "INPUT ENABLED" : "INPUT DISABLED",
    btnX + btnW/2, btnY + btnH/2);

  // ----------------------------
  // KEYBIND INFO
  // ----------------------------
  textAlign(LEFT, BASELINE);
  textSize(16);
  fill(255);

  text("FSR > 300  → ENTER", 20, 100);
  text("Flex > 500 → SPACE", 20, 125);
  text("Joystick X > 800 → D", 20, 150);
  text("Joystick X < 250 → A", 20, 175);
  text("Joystick Y > 800 → W", 20, 200);
  text("Joystick Y < 250 → S", 20, 225);

  // ----------------------------
  // LIVE SENSOR VALUES
  // ----------------------------
  fill(180);
  textSize(14);
  text("FSR: " + FSRValue, 300, 100);
  text("Flex: " + FlexValue, 300, 125);
  text("joyX: " + joyX, 300, 150);
  text("joyY: " + joyY, 300, 175);
  text("Button: " + buttonState, 300, 200);
}


// ---------------------------------------
// CLICK TO TOGGLE INPUT ON/OFF
// ---------------------------------------
void mousePressed() {
  if (mouseX > btnX && mouseX < btnX + btnW &&
    mouseY > btnY && mouseY < btnY + btnH) {

    inputEnabled = !inputEnabled;

    if (!inputEnabled) {
      releaseAllKeys();
    }
  }
}

// ---------------------------------------
// SERIAL EVENT — ONLY PROCESSES KEYS IF ENABLED
// ---------------------------------------
void serialEvent(Serial port) {
  String line = port.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);

  String[] parts = split(line, ',');
  if (parts.length < 11) {
    println("Bad packet:", line);
    return;
  }

  try {
    FSRValue  = int(parts[0].trim());
    FlexValue = int(parts[1].trim());
    joyX      = int(parts[8].trim());
    joyY      = int(parts[9].trim());
    buttonState = int(parts[10].trim());
  }
  catch (Exception e) {
    println("Parse error:", e);
    return;
  }

  if (!inputEnabled) return; // IMPORTANT: ignore key logic

  // =====================================================
  // FSR → ENTER
  // =====================================================
  if (FSRValue > 300) {
    if (!enterDown) {
      bot.keyPress(KeyEvent.VK_ENTER);
      enterDown = true;
    }
  } else {
    if (enterDown) {
      bot.keyRelease(KeyEvent.VK_ENTER);
      enterDown = false;
    }
  }

  // =====================================================
  // FLEX → SPACE
  // =====================================================
  if (FlexValue < 70) {
    if (!spaceDown) {
      bot.keyPress(KeyEvent.VK_SPACE);
      spaceDown = true;
    }
  } else {
    if (spaceDown) {
      bot.keyRelease(KeyEvent.VK_SPACE);
      spaceDown = false;
    }
  }

  // =====================================================
  // JOYSTICK X → A or D
  // =====================================================
  // JOYSTICK X → A or D (FLIPPED LEFT/RIGHT)
  if (joyX > 800) {
    // previously D, now LEFT
    if (!aDown) {
      bot.keyPress(KeyEvent.VK_A);
      aDown = true;
    }
    if (dDown) {
      bot.keyRelease(KeyEvent.VK_D);
      dDown = false;
    }
  } else if (joyX < 250) {
    // previously A, now RIGHT
    if (!dDown) {
      bot.keyPress(KeyEvent.VK_D);
      dDown = true;
    }
    if (aDown) {
      bot.keyRelease(KeyEvent.VK_A);
      aDown = false;
    }
  } else {
    // neutral zone → release both
    if (aDown) {
      bot.keyRelease(KeyEvent.VK_A);
      aDown = false;
    }
    if (dDown) {
      bot.keyRelease(KeyEvent.VK_D);
      dDown = false;
    }
  }


  // =====================================================
  // JOYSTICK Y → W or S
  // =====================================================
  if (joyY > 800) {
    if (!wDown) {
      bot.keyPress(KeyEvent.VK_W);
      wDown = true;
    }
    if (sDown) {
      bot.keyRelease(KeyEvent.VK_S);
      sDown = false;
    }
  } else if (joyY < 250) {
    if (!sDown) {
      bot.keyPress(KeyEvent.VK_S);
      sDown = true;
    }
    if (wDown) {
      bot.keyRelease(KeyEvent.VK_W);
      wDown = false;
    }
  } else {
    if (wDown) {
      bot.keyRelease(KeyEvent.VK_W);
      wDown = false;
    }
    if (sDown) {
      bot.keyRelease(KeyEvent.VK_S);
      sDown = false;
    }
  }
}

// -------------------------------------------------------
// RELEASE ALL KEYS SAFELY
// -------------------------------------------------------
void releaseAllKeys() {
  if (enterDown) bot.keyRelease(KeyEvent.VK_ENTER);
  if (spaceDown) bot.keyRelease(KeyEvent.VK_SPACE);
  if (aDown) bot.keyRelease(KeyEvent.VK_A);
  if (dDown) bot.keyRelease(KeyEvent.VK_D);
  if (wDown) bot.keyRelease(KeyEvent.VK_W);
  if (sDown) bot.keyRelease(KeyEvent.VK_S);

  enterDown = spaceDown = false;
  aDown = dDown = false;
  wDown = sDown = false;
}

// -------------------------------------------------------
// CLEAN EXIT — RELEASE ALL KEYS
// -------------------------------------------------------
void exit() {
  releaseAllKeys();
  super.exit();
}

// -------------------------------------------------------
// SERIAL SETUP (UNCHANGED)
// -------------------------------------------------------
void setupSerial() {
  println("Serial ports:");
  String[] ports = Serial.list();
  for (int i = 0; i < ports.length; i++) println("  [" + i + "] " + ports[i]);
  if (ports.length == 0) {
    println("No serial ports found.");
    return;
  }

  String chosen;
  if (SERIAL_PORT_INDEX >= 0 && SERIAL_PORT_INDEX < ports.length) {
    chosen = ports[SERIAL_PORT_INDEX];
  } else {
    chosen = ports[ports.length - 1];
  }

  println("Opening serial on " + chosen + " at 115200...");
  try {
    myPort = new Serial(this, chosen, 115200);
    println("✅ Serial opened successfully!");
  }
  catch (Exception e) {
    println("❌ Failed to open serial:", e.getMessage());
  }
}
