/*
 * Diagnostic: test each GPIO pin individually.
 * Tests HIGH and LOW on each pin for 3 seconds.
 * Upload, watch the LEDs, report which steps lit which colors.
 */

#define RED_PIN    2
#define YELLOW_PIN 1
#define GREEN_PIN  0

void setup() {
  Serial.begin(115200);
  delay(1000);
  pinMode(RED_PIN, OUTPUT);
  pinMode(YELLOW_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);

  allOff();
  delay(1000);

  Serial.println("=== HERMES TRAFFIC LIGHT DIAGNOSTIC ===");
  Serial.println("");

  Serial.println("[1/6] RED (GPIO2) HIGH");
  digitalWrite(RED_PIN, HIGH);
  delay(3000);
  allOff();
  delay(500);

  Serial.println("[2/6] RED (GPIO2) LOW");
  digitalWrite(RED_PIN, LOW);
  delay(3000);
  allOff();
  delay(500);

  Serial.println("[3/6] YELLOW (GPIO1) HIGH");
  digitalWrite(YELLOW_PIN, HIGH);
  delay(3000);
  allOff();
  delay(500);

  Serial.println("[4/6] YELLOW (GPIO1) LOW");
  digitalWrite(YELLOW_PIN, LOW);
  delay(3000);
  allOff();
  delay(500);

  Serial.println("[5/6] GREEN (GPIO0) HIGH");
  digitalWrite(GREEN_PIN, HIGH);
  delay(3000);
  allOff();
  delay(500);

  Serial.println("[6/6] GREEN (GPIO0) LOW");
  digitalWrite(GREEN_PIN, LOW);
  delay(3000);
  allOff();

  Serial.println("=== DONE ===");
}

void loop() {}

void allOff() {
  digitalWrite(RED_PIN, LOW);
  digitalWrite(YELLOW_PIN, LOW);
  digitalWrite(GREEN_PIN, LOW);
}
