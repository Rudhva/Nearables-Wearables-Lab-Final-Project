/*
COLOR 1 = Glases Width
Color 2 = Glasses Height
Colro 3 = Lips Height 
*/

import processing.video.*;

Capture cam;

// =====================
// CALIBRATION COLORS
// =====================
color color1 = color(0, 255, 0);    // glasses width dots
color color2 = color(255, 255, 0);  // glasses height dots
color color3 = color(0, 128, 255);  // lips dots

float thresh1 = 40;
float thresh2 = 40;
float thresh3 = 40;

// =====================
// REAL-WORLD VALUES (SET THESE!)
// =====================
float glassesRealWidthMM  = 100.0;   // TODO measure your glasses
float glassesRealHeightMM = 20.0;    // TODO measure glasses lens height

// =====================
// DETECTED VALUES
// =====================
boolean found1 = false;  // width dots
boolean found2 = false;  // height dots
boolean found3 = false;  // lips dots

float minX1 = Float.MAX_VALUE, maxX1 = -Float.MAX_VALUE;
float minY2 = Float.MAX_VALUE, maxY2 = -Float.MAX_VALUE;

float lipTopY = Float.MAX_VALUE;
float lipBottomY = -Float.MAX_VALUE;

float widthPx  = 0;
float heightPx = 0;
float jawPx    = 0;

float mmPerPx = 0;
float mmPerPx_W = 0;
float mmPerPx_H = 0;
float jawMM = 0;

// =====================
// CAMERA + CALIB UI
// =====================
float winScale = 1.3;
float calibX1, calibY1;
float calibX2, calibY2;
float calibX3, calibY3;

int step = 3;

void settings() {
  size(int(640 * winScale), int(480 * winScale));
}

void setup() {
  String[] cams = Capture.list();
  if (cams.length == 0) exit();

  cam = new Capture(this, cams[0]);
  cam.start();

  calibX1 = width * 0.25; calibY1 = height * 0.5;
  calibX2 = width * 0.75; calibY2 = height * 0.5;
  calibX3 = width * 0.50; calibY3 = height * 0.75;

  textFont(createFont("Arial", 16));
}

void draw() {
  background(0);

  if (cam.available())
    cam.read();

  cam.loadPixels();
  int w = cam.width;
  int h = cam.height;

  // CAMERA DRAW (mirrored)
  pushMatrix();
  scale(-1, 1);
  image(cam, -width, 0, width, height);
  popMatrix();

  // RESET DETECTION
  resetDetection();

  // DETECT DOT GROUPS
  detectDots(w, h);

  // COMPUTE MEASUREMENTS
  computeJaw();

  // DRAW RESULTS
  drawOverlays();
  drawLegend();
}

// ==============================================
// RESET FOR EACH FRAME
// ==============================================
void resetDetection() {
  found1 = found2 = found3 = false;

  minX1 = Float.MAX_VALUE; maxX1 = -Float.MAX_VALUE;
  minY2 = Float.MAX_VALUE; maxY2 = -Float.MAX_VALUE;

  lipTopY = Float.MAX_VALUE;
  lipBottomY = -Float.MAX_VALUE;
}

// ==============================================
// DETECT ALL DOTS
// ==============================================
void detectDots(int w, int h) {
  for (int y = 0; y < h; y += step) {
    int row = y * w;
    for (int x = 0; x < w; x += step) {
      color c = cam.pixels[row + x];

      // ---------- COLOR 1: WIDTH (GREEN) ----------
      if (colorDist(c, color1) < thresh1) {
        found1 = true;
        if (x < minX1) minX1 = x;
        if (x > maxX1) maxX1 = x;
      }

      // ---------- COLOR 2: HEIGHT (YELLOW) ----------
      if (colorDist(c, color2) < thresh2) {
        found2 = true;
        if (y < minY2) minY2 = y;
        if (y > maxY2) maxY2 = y;
      }

      // ---------- COLOR 3: LIPS (BLUE) ----------
      if (colorDist(c, color3) < thresh3) {
        found3 = true;
        if (y < lipTopY) lipTopY = y;
        if (y > lipBottomY) lipBottomY = y;
      }
    }
  }

  // finalize px distances
  if (found1) widthPx  = maxX1 - minX1;
  if (found2) heightPx = maxY2 - minY2;
  if (found3) jawPx    = lipBottomY - lipTopY;
}

// ==============================================
// COMPUTE JAW OPENING IN MM
// ==============================================
void computeJaw() {
  jawMM = 0;
  mmPerPx = 0;

  if (found1 && widthPx > 1)
    mmPerPx_W = glassesRealWidthMM / widthPx;
  if (found2 && heightPx > 1)
    mmPerPx_H = glassesRealHeightMM / heightPx;

  // Average both axes for accuracy
  if (mmPerPx_W > 0 && mmPerPx_H > 0)
    mmPerPx = (mmPerPx_W + mmPerPx_H) * 0.5;
  else if (mmPerPx_W > 0)
    mmPerPx = mmPerPx_W;
  else if (mmPerPx_H > 0)
    mmPerPx = mmPerPx_H;

  if (found3 && mmPerPx > 0)
    jawMM = jawPx * mmPerPx;
}

// ==============================================
// DRAW OVERLAYS
// ==============================================
void drawOverlays() {
  float sx = width / float(cam.width);
  float sy = height / float(cam.height);

  // Calibration circles
  noFill(); strokeWeight(2);
  stroke(0, 255, 0); ellipse(calibX1, calibY1, 30, 30);
  stroke(255, 255, 0); ellipse(calibX2, calibY2, 30, 30);
  stroke(0, 128, 255); ellipse(calibX3, calibY3, 30, 30);

  // Width line
  if (found1) {
    float xs = (cam.width - maxX1) * sx;
    float xe = (cam.width - minX1) * sx;
    float ymid = height * 0.4;

    stroke(0, 255, 0);
    strokeWeight(3);
    line(xs, ymid, xe, ymid);
  }

  // Height line
  if (found2) {
    float xm = width * 0.5;
    float ys = minY2 * sy;
    float ye = maxY2 * sy;

    stroke(255, 255, 0);
    strokeWeight(3);
    line(xm, ys, xm, ye);
  }

  // Lips vertical line
  if (found3) {
    float xm = width * 0.5;
    float ys = lipTopY * sy;
    float ye = lipBottomY * sy;

    stroke(0, 128, 255);
    strokeWeight(3);
    line(xm, ys, xm, ye);
  }
}

// ==============================================
// LEGEND
// ==============================================
void drawLegend() {
  fill(0, 0, 0, 150);
  noStroke();
  rect(10, 10, 320, 160);

  fill(255);
  textAlign(LEFT, TOP);

  text("Width real: " + glassesRealWidthMM + " mm", 20, 20);
  text("Height real: " + glassesRealHeightMM + " mm", 20, 40);

  text("Width px: "  + nf(widthPx, 0, 1), 20, 65);
  text("Height px: " + nf(heightPx, 0, 1), 20, 85);

  text("mm per px: " + nf(mmPerPx, 0, 3), 20, 110);

  text("Jaw px: " + nf(jawPx, 0, 1), 20, 135);
  text("Jaw mm: " + nf(jawMM, 0, 2), 20, 155);
}

// ==============================================
// CALIBRATION KEYS
// ==============================================
void keyPressed() {
  cam.loadPixels();

  if (key == '1') {    // calibrate color 1
    int sx = int(map(calibX1, 0, width, 0, cam.width));
    int sy = int(map(calibY1, 0, height, 0, cam.height));
    sx = constrain(sx, 0, cam.width - 1);
    sy = constrain(sy, 0, cam.height - 1);

    color1 = cam.pixels[sx + sy * cam.width];
    println("Color 1 calibrated:", red(color1), green(color1), blue(color1));
  }

  if (key == '2') {    // calibrate color 2
    int sx = int(map(calibX2, 0, width, 0, cam.width));
    int sy = int(map(calibY2, 0, height, 0, cam.height));
    sx = constrain(sx, 0, cam.width - 1);
    sy = constrain(sy, 0, cam.height - 1);

    color2 = cam.pixels[sx + sy * cam.width];
    println("Color 2 calibrated:", red(color2), green(color2), blue(color2));
  }

  if (key == '3') {    // calibrate color 3
    int sx = int(map(calibX3, 0, width, 0, cam.width));
    int sy = int(map(calibY3, 0, height, 0, cam.height));
    sx = constrain(sx, 0, cam.width - 1);
    sy = constrain(sy, 0, cam.height - 1);

    color3 = cam.pixels[sx + sy * cam.width];
    println("Color 3 calibrated:", red(color3), green(color3), blue(color3));
  }
}

// ==============================================
// COLOR DISTANCE
// ==============================================
float colorDist(color a, color b) {
  float dr = red(a) - red(b);
  float dg = green(a) - green(b);
  float db = blue(a) - blue(b);
  return sqrt(dr*dr + dg*dg + db*db);
}
