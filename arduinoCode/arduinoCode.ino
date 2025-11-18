int FSRvalue, Flexvalue;

void setup() {
  pinMode(10, OUTPUT);  // LED su pin PWM
  pinMode(A0, INPUT);   // FSR
  pinMode(A2, INPUT);   // Flex sensor

  Serial.begin(115200); // << INDISPENSABILE per vedere i valori
}

void loop() {
  analogWrite(10, 100);  // Accende il LED a luminosità media

  FSRvalue  = analogRead(A0);
  Flexvalue = analogRead(A2);

  // stampa i valori
  serialPrint(FSRvalue, Flexvalue);

  delay(50); // leggero delay
}

void serialPrint(int fsr, int flex) {
  Serial.print("FSR: ");
  Serial.print(fsr);
  Serial.print("   Flex: ");
  Serial.println(flex);
}

