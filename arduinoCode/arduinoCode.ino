#include <Wire.h>
#include <MPU6050.h>

MPU6050 mpu;

// Sensors
int FSRvalue, Flexvalue;
int16_t ax, ay, az;
int16_t gx, gy, gz;
float ax_g, ay_g, az_g;
float gx_dps, gy_dps, gz_dps;
int x_val, y_val, button_state;

void setup() {
  Serial.begin(115200);
  Wire.begin();

  pinMode(10, OUTPUT);       // LED
  pinMode(A2, INPUT);        // FSR
  pinMode(A4, INPUT);        // Flex sensor
  pinMode(A0, INPUT);        // Joystick X
  pinMode(A1, INPUT);        // Joystick Y
  pinMode(7, INPUT_PULLUP);  // Joystick button

  // MPU initialize
  Serial.println("Initializing MPU6050...");
  mpu.initialize();

  if (!mpu.testConnection()) {
    Serial.println("Error: MPU6050 not connected!");
    while (1)
      ;
  }
  Serial.println("MPU6050 connected.");
  Serial.println("Setup successful.\n");
}

void loop() {
  analogWrite(10, 100);  // LED medium brightness

  // Read sensors
  FSRvalue = analogRead(A2);
  Flexvalue = analogRead(A4);

  mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

  ax_g = ax / 16384.0;
  ay_g = ay / 16384.0;
  az_g = az / 16384.0;
  gx_dps = gx / 131.0;
  gy_dps = gy / 131.0;
  gz_dps = gz / 131.0;

  x_val = analogRead(A0);
  y_val = analogRead(A1);
  button_state = digitalRead(7);

  // DO NOT CHANGE THIS ORDER (requested)
  serialPrint(FSRvalue, Flexvalue,
              ax_g, ay_g, az_g,
              gx_dps, gy_dps, gz_dps,
              x_val, y_val, button_state);

  delay(50);
}

void serialPrint(int fsr, int flex,
                 float ax, float ay, float az,
                 float gx, float gy, float gz,
                 int x, int y, int button_state) {
  Serial.print(fsr);
  Serial.print(", ");
  Serial.print(flex);
  Serial.print(", ");
  Serial.print(ax);
  Serial.print(", ");
  Serial.print(ay);
  Serial.print(", ");
  Serial.print(az);
  Serial.print(", ");
  Serial.print(gx);
  Serial.print(", ");
  Serial.print(gy);
  Serial.print(", ");
  Serial.print(gz);
  Serial.print(", ");
  Serial.print(x);
  Serial.print(", ");
  Serial.print(y);
  Serial.print(", ");
  Serial.println(button_state);
}
