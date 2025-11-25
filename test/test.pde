import processing.serial.*;

Serial primary, secondary;
String primaryName = "";
String secondaryName = "";
String lastPrimary = "";
String lastSecondary = "";
int countPrimary = 0;
int countSecondary = 0;

void settings() {
  size(720, 220);
}

void setup() {
  textFont(createFont("Arial", 14));
  println("Two-port smoke test. Press 'r' to reconnect.");
  openPorts();
}

void draw() {
  background(24);
  fill(255);
  text("Ports detected: " + join(Serial.list(), ", "), 12, 24);
  text("Primary (last): " + (primaryName.equals("") ? "none" : primaryName) + "  packets: " + countPrimary, 12, 54);
  text("Secondary (2nd last): " + (secondaryName.equals("") ? "none" : secondaryName) + "  packets: " + countSecondary, 12, 78);

  fill(180);
  text("Last primary packet:", 12, 110);
  text(lastPrimary, 12, 128, width - 24, 32);
  text("Last secondary packet:", 12, 160);
  text(lastSecondary, 12, 178, width - 24, 32);
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    println("Reconnecting...");
    openPorts();
  }
}

void serialEvent(Serial port) {
  String line = port.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  if (port == primary) {
    lastPrimary = line;
    countPrimary++;
  } else if (port == secondary) {
    lastSecondary = line;
    countSecondary++;
  }
}

void openPorts() {
  closePorts();
  String[] ports = Serial.list();
  if (ports.length == 0) {
    println("No serial ports found.");
    primaryName = secondaryName = "";
    return;
  }

  // Primary = last port
  try {
    primaryName = ports[ports.length - 1];
    println("Opening primary on " + primaryName);
    primary = new Serial(this, primaryName, 115200);
    primary.clear();
  }
  catch (Exception e) {
    println("Failed to open primary: " + e.getMessage());
    primary = null;
    primaryName = "";
  }

  // Small pause before opening the second port
  delay(2000);

  // Secondary = second-to-last port (if available)
  if (ports.length >= 2) {
    try {
      secondaryName = ports[ports.length - 2];
      println("Opening secondary on " + secondaryName);
      secondary = new Serial(this, secondaryName, 115200);
      secondary.clear();
    }
    catch (Exception e) {
      println("Failed to open secondary: " + e.getMessage());
      secondary = null;
      secondaryName = "";
    }
  } else {
    secondaryName = "";
    println("Only one port available; secondary not opened.");
  }

  lastPrimary = lastSecondary = "";
  countPrimary = countSecondary = 0;
}

void closePorts() {
  try {
    if (primary != null) primary.stop();
  } catch (Exception ignored) {
  }
  try {
    if (secondary != null) secondary.stop();
  } catch (Exception ignored) {
  }
  primary = secondary = null;
}
