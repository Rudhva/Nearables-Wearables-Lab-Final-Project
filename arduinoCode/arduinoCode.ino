// ----------------------
// Basic Joystick Reader
// ----------------------

int joyX = A0;    // Joystick X-axis
int joyY = A1;    // Joystick Y-axis
int joyBtn = 2;   // Joystick pushbutton (active LOW)

void setup() {
  Serial.begin(9600);

  pinMode(joyBtn, INPUT_PULLUP);  // Button reads LOW when pressed
}

void loop() {
  int xVal = analogRead(joyX);    // 0–1023
  int yVal = analogRead(joyY);    // 0–1023
  int btn  = digitalRead(joyBtn); // 1 = not pressed, 0 = pressed

  Serial.print("X: ");
  Serial.print(xVal);
  Serial.print(" | Y: ");
  Serial.print(yVal);
  Serial.print(" | Button: ");
  Serial.println(btn == LOW ? "Pressed" : "Released");

  delay(100); // slow the output
}
