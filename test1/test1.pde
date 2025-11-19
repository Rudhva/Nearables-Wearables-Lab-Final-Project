import processing.video.*;

Capture cam;

// --- Calibration + Tracking ---
color targetColor = color(255, 0, 0);
float threshold = 40;

// ================= SECOND COLOR ADDITIONS =================
color targetColor2 = color(0, 255, 0);
volatile int detectedX2 = -1;
volatile int detectedY2 = -1;
volatile float detectedBestDist2 = 1e9;
volatile int lastX2 = -1;
volatile int lastY2 = -1;
volatile boolean hasLast2 = false;
// ===========================================================

// --- Smoothing ---
float smoothX = -1;
float smoothY = -1;
float alpha = 0.5;

// ================= SECOND COLOR ADDITIONS =================
float smoothX2 = -1;
float smoothY2 = -1;
// ===========================================================

// --- UI ---
float winScale = 1.5;
float calibrateX, calibrateY;

// ================= SECOND COLOR ADDITIONS =================
float calibrateX2, calibrateY2;
// ===========================================================

// --- Thread + tracking state ---
volatile boolean threadRunning = true;

// shared frame buffer (copy of cam.pixels)
int[] framePixels = null;
volatile int frameW = 0;
volatile int frameH = 0;

// detection result from thread (camera coords, NOT mirrored)
volatile int detectedX = -1;
volatile int detectedY = -1;
volatile float detectedBestDist = 1e9;

// window-search state (in camera coords)
volatile int lastX = -1;
volatile int lastY = -1;
volatile boolean hasLast = false;

// scanning parameters
int step = 3;
int windowRadius = 100;

void settings() {
  size(int(640 * winScale), int(480 * winScale));
}

void setup() {
  String[] cams = Capture.list();
  if (cams.length == 0) {
    println("No cameras found.");
    exit();
  }

  cam = new Capture(this, cams[0]);
  cam.start();

  calibrateX = width * 0.33;
  calibrateY = height * 0.5;

  // ================= SECOND COLOR ADDITIONS =================
  calibrateX2 = width * 0.66;
  calibrateY2 = height * 0.5;
  // ===========================================================

  thread("trackerThread");
  thread("trackerThread2");     // <-- NEW SECOND THREAD
}

void draw() {
  if (cam.available()) {
    cam.read();
    cam.loadPixels();

    if (framePixels == null || framePixels.length != cam.pixels.length) {
      framePixels = new int[cam.pixels.length];
    }
    arrayCopy(cam.pixels, framePixels);
    frameW = cam.width;
    frameH = cam.height;
  }

  pushMatrix();
  scale(-1, 1);
  image(cam, -width, 0, width, height);
  popMatrix();

  trackColorFromThread();
  trackColor2FromThread();   // <-- NEW DRAW FUNCTION

  noFill();
  stroke(255, 0, 0);
  strokeWeight(2);
  ellipse(calibrateX, calibrateY, 20, 20);

  // ================= SECOND COLOR ADDITIONS =================
  stroke(0, 255, 0);
  ellipse(calibrateX2, calibrateY2, 20, 20);
  // ==========================================================

  fill(255);
  textSize(16);
  text("Move object to circles + press SPACE to calibrate both", 10, height - 10);
}

void trackColorFromThread() {
  int bestX_cam = detectedX;
  int bestY_cam = detectedY;
  float bestDist = detectedBestDist;

  if (bestX_cam < 0 || bestY_cam < 0 || bestDist > threshold) {
    hasLast = false;
    return;
  }

  lastX = bestX_cam;
  lastY = bestY_cam;
  hasLast = true;

  int bestX_mirror_cam = frameW - bestX_cam;
  int bestY_mirror_cam = bestY_cam;

  float drawX = bestX_mirror_cam * (width / float(frameW));
  float drawY = bestY_mirror_cam * (height / float(frameH));

  if (smoothX < 0) {
    smoothX = drawX;
    smoothY = drawY;
  } else {
    smoothX = lerp(smoothX, drawX, alpha);
    smoothY = lerp(smoothY, drawY, alpha);
  }

  fill(0, 255, 0);
  noStroke();
  ellipse(smoothX, smoothY, 25, 25);
}

// ================= SECOND COLOR ADDITIONS =================
void trackColor2FromThread() {
  int bestX_cam = detectedX2;
  int bestY_cam = detectedY2;
  float bestDist = detectedBestDist2;

  if (bestX_cam < 0 || bestY_cam < 0 || bestDist > threshold) {
    hasLast2 = false;
    return;
  }

  lastX2 = bestX_cam;
  lastY2 = bestY_cam;
  hasLast2 = true;

  int bestX_mirror_cam = frameW - bestX_cam;
  int bestY_mirror_cam = bestY_cam;

  float drawX = bestX_mirror_cam * (width / float(frameW));
  float drawY = bestY_mirror_cam * (height / float(frameH));

  if (smoothX2 < 0) {
    smoothX2 = drawX;
    smoothY2 = drawY;
  } else {
    smoothX2 = lerp(smoothX2, drawX, alpha);
    smoothY2 = lerp(smoothY2, drawY, alpha);
  }

  fill(255, 255, 0);   // yellow dot for 2nd color
  noStroke();
  ellipse(smoothX2, smoothY2, 25, 25);
}
// ===========================================================

void keyPressed() {
  if (key == ' ') {
    int sx = int(map(calibrateX, 0, width, 0, cam.width));
    int sy = int(map(calibrateY, 0, height, 0, cam.height));

    cam.loadPixels();
    sx = constrain(sx, 0, cam.width - 1);
    sy = constrain(sy, 0, cam.height - 1);
    targetColor = cam.pixels[sx + sy * cam.width];

    println("🎯 Primary calibrated:", red(targetColor), green(targetColor), blue(targetColor));

    // ================= SECOND COLOR ADDITIONS =================
    int sx2 = int(map(calibrateX2, 0, width, 0, cam.width));
    int sy2 = int(map(calibrateY2, 0, height, 0, cam.height));
    sx2 = constrain(sx2, 0, cam.width - 1);
    sy2 = constrain(sy2, 0, cam.height - 1);
    targetColor2 = cam.pixels[sx2 + sy2 * cam.width];

    println("🎯 Secondary calibrated:", red(targetColor2), green(targetColor2), blue(targetColor2));
    // ===========================================================
  }
}

float colorDist(color c1, color c2) {
  float dr = red(c1) - red(c2);
  float dg = green(c1) - green(c2);
  float db = blue(c1) - blue(c2);
  return sqrt(dr*dr + dg*dg + db*db);
}

void trackerThread() {
  while (threadRunning) {
    if (framePixels == null || frameW == 0 || frameH == 0) {
      delay(1);
      continue;
    }

    int w = frameW;
    int h = frameH;
    int[] pixels = framePixels;

    color tc = targetColor;

    int minX = 0, maxX = w, minY = 0, maxY = h;

    if (hasLast) {
      minX = max(0, lastX - windowRadius);
      maxX = min(w, lastX + windowRadius);
      minY = max(0, lastY - windowRadius);
      maxY = min(h, lastY + windowRadius);
    }

    float bestDist = Float.MAX_VALUE;
    int bestX = -1, bestY = -1;

    for (int y = minY; y < maxY; y += step) {
      int rowOffset = y * w;
      for (int x = minX; x < maxX; x += step) {
        float d = colorDist(pixels[rowOffset + x], tc);
        if (d < bestDist) {
          bestDist = d;
          bestX = x;
          bestY = y;
        }
      }
    }

    detectedX = bestX;
    detectedY = bestY;
    detectedBestDist = (bestX == -1) ? Float.MAX_VALUE : bestDist;
  }
}

// ================= SECOND COLOR ADDITIONS =================
void trackerThread2() {
  while (threadRunning) {
    if (framePixels == null || frameW == 0 || frameH == 0) {
      delay(1);
      continue;
    }

    int w = frameW;
    int h = frameH;
    int[] pixels = framePixels;

    color tc = targetColor2;

    int minX = 0, maxX = w, minY = 0, maxY = h;

    if (hasLast2) {
      minX = max(0, lastX2 - windowRadius);
      maxX = min(w, lastX2 + windowRadius);
      minY = max(0, lastY2 - windowRadius);
      maxY = min(h, lastY2 + windowRadius);
    }

    float bestDist = Float.MAX_VALUE;
    int bestX = -1, bestY = -1;

    for (int y = minY; y < maxY; y += step) {
      int rowOffset = y * w;
      for (int x = minX; x < maxX; x += step) {
        float d = colorDist(pixels[rowOffset + x], tc);
        if (d < bestDist) {
          bestDist = d;
          bestX = x;
          bestY = y;
        }
      }
    }

    detectedX2 = bestX;
    detectedY2 = bestY;
    detectedBestDist2 = (bestX == -1) ? Float.MAX_VALUE : bestDist;
  }
}
// ===========================================================

void exit() {
  threadRunning = false;
  super.exit();
}
