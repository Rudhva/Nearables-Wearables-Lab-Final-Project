import processing.video.*;
import java.awt.Robot;

Capture cam;
Robot bot;

// --- Color Tracking ---
color targetColor = color(255, 0, 0);
float threshold = 40;

// --- Smoothing ---
float smoothX = -1;
float smoothY = -1;
float alpha = 0.4;

// --- Calibration UI ---
float winScale = 1.3;
float calibrateX, calibrateY;

// --- Threaded Tracking ---
volatile boolean threadRunning = true;

int[] framePixels = null;
volatile int frameW = 0;
volatile int frameH = 0;

volatile int detectedX = -1;
volatile int detectedY = -1;
volatile float detectedBestDist = 1e9;
volatile int lastX = -1, lastY = -1;
volatile boolean hasLast = false;

// scanning parameters
int step = 3;          // how sparse the scan is (bigger = faster, less precise)
int windowRadius = 100; // search window radius around last position


// --- User Toggle ---
boolean trackingEnabled = true;
boolean mouseGrabbed = false;

// --- Screen aspect ratio (MacBook Air M3: 2560x1664) ---
float screenAspect = 2560.0 / 1664.0;
float boxScale = 0.75;   // 75% of maximum size (change this!)


// Auto-scaled box variables
float boxX, boxY, boxW, boxH;


void settings() {
  size(int(640 * winScale), int(480 * winScale));
}

void setup() {
  String[] cams = Capture.list();
  if (cams.length == 0) exit();
  cam = new Capture(this, cams[0]);
  cam.start();

  try {
    bot = new Robot();
  } catch (Exception e) {}

  calibrateX = width * 0.5;
  calibrateY = height * 0.5;

  computeTrackingBox();
  thread("trackerThread");
}

void computeTrackingBox() {
  // largest rectangle with aspect ratio screenAspect
  float maxW, maxH;

  if (width / float(height) > screenAspect) {
    maxH = height;
    maxW = maxH * screenAspect;
  } else {
    maxW = width;
    maxH = maxW / screenAspect;
  }

  // apply scale factor
  boxW = maxW * boxScale;
  boxH = maxH * boxScale;

  // center it
  boxX = (width - boxW) / 2;
  boxY = (height - boxH) / 2;
}


void draw() {
  background(0);

  if (cam.available()) {
    cam.read();
    cam.loadPixels();

    if (framePixels == null)
      framePixels = new int[cam.pixels.length];

    arrayCopy(cam.pixels, framePixels);
    frameW = cam.width;
    frameH = cam.height;
  }

  // draw mirrored camera preview
  pushMatrix();
  scale(-1, 1);
  image(cam, -width, 0, width, height);
  popMatrix();

  // draw the tracking box (RED)
  noFill();
  stroke(255, 0, 0);
  strokeWeight(3);
  rect(boxX, boxY, boxW, boxH);

  // draw dot
  trackColorFromThread();

  // draw UI text
  drawUI();

  // handle mouse control
  if (trackingEnabled) {
    controlMouse();
  } else {
    mouseGrabbed = false;
  }
}

void drawUI() {
  fill(255);
  textSize(18);
  text("SPACE: calibrate color", 10, height - 50);
  text("'T': toggle tracking (" + (trackingEnabled ? "ON" : "OFF") + ")", 10, height - 25);

  // calibration circle
  noFill();
  stroke(255, 0, 0);
  strokeWeight(2);
  ellipse(calibrateX, calibrateY, 20, 20);
}

void keyPressed() {
  if (key == ' ') {
    int sx = int(map(calibrateX, 0, width, 0, cam.width));
    int sy = int(map(calibrateY, 0, height, 0, cam.height));

    cam.loadPixels();
    sx = constrain(sx, 0, cam.width - 1);
    sy = constrain(sy, 0, cam.height - 1);

    targetColor = cam.pixels[sx + sy * cam.width];
    println("Calibrated:", red(targetColor), green(targetColor), blue(targetColor));
  }

  if (key == 't' || key == 'T') {
    trackingEnabled = !trackingEnabled;
  }
}

void trackColorFromThread() {
  int bx = detectedX;
  int by = detectedY;
  float dist = detectedBestDist;

  if (bx < 0 || by < 0 || dist > threshold) {
    hasLast = false;
    return;
  }

  lastX = bx;
  lastY = by;
  hasLast = true;

  int mx = frameW - bx;   // horizontal mirror
  int my = by;

  float dx = mx * (width / float(frameW));
  float dy = my * (height / float(frameH));

  if (smoothX < 0) {
    smoothX = dx;
    smoothY = dy;
  } else {
    smoothX = lerp(smoothX, dx, alpha);
    smoothY = lerp(smoothY, dy, alpha);
  }

  // NEON PINK dot
  fill(255, 0, 180);
  noStroke();
  ellipse(smoothX, smoothY, 25, 25);
}

float colorDist(color c1, color c2) {
  float dr = red(c1) - red(c2);
  float dg = green(c1) - green(c2);
  float db = blue(c1) - blue(c2);
  return sqrt(dr*dr + dg*dg + db*db);
}

void trackerThread() {
  while (threadRunning) {
    if (framePixels == null) {
      delay(1);
      continue;
    }

    int w = frameW;
    int h = frameH;
    int[] px = framePixels;
    color tc = targetColor;

    int minX = 0, maxX = w;
    int minY = 0, maxY = h;

    if (hasLast) {
      minX = max(0, lastX - windowRadius);
      maxX = min(w, lastX + windowRadius);
      minY = max(0, lastY - windowRadius);
      maxY = min(h, lastY + windowRadius);
    }

    float best = Float.MAX_VALUE;
    int bx = -1, by = -1;

    for (int y = minY; y < maxY; y += step) {
      int off = y * w;
      for (int x = minX; x < maxX; x += step) {
        float d = colorDist(px[off + x], tc);
        if (d < best) {
          best = d;
          bx = x;
          by = y;
        }
      }
    }

    detectedX = bx;
    detectedY = by;
    detectedBestDist = best;
  }
}

void controlMouse() {
  if (!hasLast || detectedBestDist > threshold) {
    mouseGrabbed = false;
    return;
  }

  // Only move mouse if dot is inside the box
  if (smoothX < boxX || smoothX > boxX + boxW ||
      smoothY < boxY || smoothY > boxY + boxH) {
    mouseGrabbed = false;
    return;
  }

  mouseGrabbed = true;

  // Map dot inside box → full screen
  float normX = (smoothX - boxX) / boxW;
  float normY = (smoothY - boxY) / boxH;

  int screenX = int(normX * displayWidth);
  int screenY = int(normY * displayHeight);

  bot.mouseMove(screenX, screenY);
}

void exit() {
  threadRunning = false;
  super.exit();
}
