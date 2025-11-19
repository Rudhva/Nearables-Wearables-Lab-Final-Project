import java.awt.Robot;
import processing.serial.*;

Robot bot;
Serial myPort;

// Joystick raw data
int joyX = 0;
int joyY = 0;

// Movement settings
float speed = 5;      // base speed (slider controlled)
int deadzone = 100;   // amount joystick can wobble without moving mouse

// UI slider
float sliderX = 40;
float sliderY = 120;
float sliderW = 300;
float sliderH = 20;
boolean sliding = false;

int SERIAL_PORT_INDEX = -1;

void setup() {
  size(400, 250);
  try {
    bot = new Robot();
  }
  catch(Exception e) {
    println("Robot init error: " + e);
  }
  setupSerial();
}

void draw() {
  background(25);

  // ---------------------------
  // SPEED SLIDER UI
  // ---------------------------
  fill(180);
  textSize(16);
  text("Joystick Mouse Speed", 40, 80);

  // Slider background
  fill(70);
  rect(sliderX, sliderY, sliderW, sliderH, 5);

  // Slider knob (based on speed)
  float knobX = map(speed, 1, 30, sliderX, sliderX + sliderW);
  fill(200, 200, 0);
  rect(knobX - 10, sliderY - 5, 20, sliderH + 10, 5);

  fill(255);
  text("Speed: " + nf(speed, 1, 1), 40, 160);

  // ---------------------------
  // JOYSTICK → MOUSE MOVEMENT
  // ---------------------------
  moveCursorWithJoystick();
}

void mousePressed() {
  float knobX = map(speed, 1, 30, sliderX, sliderX + sliderW);
  if (mouseX > knobX - 15 && mouseX < knobX + 15 &&
      mouseY > sliderY - 10 && mouseY < sliderY + sliderH + 10)
  {
    sliding = true;
  }
}

void mouseDragged() {
  if (sliding) {
    float val = constrain(mouseX, sliderX, sliderX + sliderW);
    speed = map(val, sliderX, sliderX + sliderW, 1, 30);
  }
}

void mouseReleased() {
  sliding = false;
}

// -------------------------------------------------------
// MOVE CURSOR BASED ON JOYSTICK DIRECTION + SPEED
// -------------------------------------------------------
void moveCursorWithJoystick() {
  // Center values around zero: -512 to +512
  int dx = joyX - 512;
  int dy = joyY - 512;

  // Deadzone — prevents small noise from moving mouse
  if (abs(dx) < deadzone) dx = 0;
  if (abs(dy) < deadzone) dy = 0;

  // If joystick is neutral, do nothing
  if (dx == 0 && dy == 0) return;

  // Determine movement direction
  float moveX = (dx / 512.0) * speed;
  float moveY = (dy / 512.0) * speed;

  // Current mouse loc
  java.awt.Point p = java.awt.MouseInfo.getPointerInfo().getLocation();

  // Apply movement (inverted Y for joystick)
  bot.mouseMove(p.x + (int)moveX, p.y + (int)moveY);
}

// -------------------------------------------------------
// SERIAL EVENT — READ JOYSTICK ONLY
// -------------------------------------------------------
void serialEvent(Serial port) {
  String line = port.readStringUntil('\n');
  if (line == null) return;

  line = trim(line);
  String[] parts = split(line, ',');

  if (parts.length < 11) return;

  try {
    joyX = int(parts[8].trim());
    joyY = int(parts[9].trim());
  }
  catch(Exception e) {
    println("Parse error:", e);
  }
}

// -------------------------------------------------------
// SERIAL SETUP (unchanged from your version)
// -------------------------------------------------------
void setupSerial() {
  println("Serial ports:");
  String[] ports = Serial.list();
  for (int i = 0; i < ports.length; i++) println("[" + i + "] " + ports[i]);

  if (ports.length == 0) {
    println("No serial ports found.");
    return;
  }

  String chosen;
  if (SERIAL_PORT_INDEX >= 0 && SERIAL_PORT_INDEX < ports.length)
    chosen = ports[SERIAL_PORT_INDEX];
  else
    chosen = ports[ports.length - 1];

  println("Opening serial on " + chosen + "...");
  try {
    myPort = new Serial(this, chosen, 115200);
    myPort.clear();
    println("Serial OK");
  }
  catch (Exception e) {
    println("Serial failed: " + e.getMessage());
  }
}
