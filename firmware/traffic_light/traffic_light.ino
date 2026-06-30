/*
 * Hermes Traffic Light — XIAO ESP32-C3 + Adeept Module
 * Common cathode: HIGH = LED ON, LOW = LED OFF
 *
 * Pin mapping (verified by diagnostic firmware):
 *   Red    → GPIO2
 *   Yellow → GPIO1
 *   Green  → GPIO0
 *
 * Serial commands: "working", "waiting", "idle", "off", "test", "status"
 */

#define RED_PIN    2   // GPIO2
#define YELLOW_PIN 1   // GPIO1
#define GREEN_PIN  0   // GPIO0

#define LED_ON   HIGH
#define LED_OFF  LOW

String currentState = "idle";

void setup() {
  Serial.begin(115200);
  pinMode(RED_PIN, OUTPUT);
  pinMode(YELLOW_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);

  allOff();
  Serial.println("Hermes Traffic Light ready");
  Serial.println("Commands: working | waiting | idle | off | test | status");
}

void loop() {
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    cmd.toLowerCase();

    if (cmd == "working") {
      setState("working");
    } else if (cmd == "waiting") {
      setState("waiting");
    } else if (cmd == "idle") {
      setState("idle");
    } else if (cmd == "off") {
      setState("off");
    } else if (cmd == "test") {
      testSequence();
    } else if (cmd == "status") {
      Serial.println("STATE:" + currentState);
    } else {
      Serial.println("Unknown command: " + cmd);
    }
  }

  // Blink effects
  if (currentState == "working") {
    digitalWrite(GREEN_PIN, LED_ON);
    delay(800);
    digitalWrite(GREEN_PIN, LED_OFF);
    delay(200);
  } else if (currentState == "waiting") {
    digitalWrite(RED_PIN, LED_ON);
    delay(200);
    digitalWrite(RED_PIN, LED_OFF);
    delay(100);
  }
}

void setState(String state) {
  currentState = state;
  allOff();

  if (state == "working") {
    // Green blink handled in loop()
  } else if (state == "waiting") {
    // Red blink handled in loop()
  } else if (state == "idle") {
    digitalWrite(YELLOW_PIN, LED_ON);
  } else if (state == "off") {
    // all already off
  }

  Serial.println("STATE:" + currentState);
}

void allOff() {
  digitalWrite(RED_PIN, LED_OFF);
  digitalWrite(YELLOW_PIN, LED_OFF);
  digitalWrite(GREEN_PIN, LED_OFF);
}

void testSequence() {
  Serial.println("TEST: red");
  allOff();
  digitalWrite(RED_PIN, LED_ON);
  delay(1000);

  Serial.println("TEST: yellow");
  allOff();
  digitalWrite(YELLOW_PIN, LED_ON);
  delay(1000);

  Serial.println("TEST: green");
  allOff();
  digitalWrite(GREEN_PIN, LED_ON);
  delay(1000);

  allOff();
  Serial.println("TEST: done");
  setState(currentState);
}
