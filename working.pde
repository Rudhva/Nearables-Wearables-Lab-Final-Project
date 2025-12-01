import processing.video.*;
import processing.serial.*;
import java.util.ArrayList;
import java.awt.Robot;
import java.awt.event.InputEvent;

// ---------- App + camera ----------
int playerCount = 1;   // 1 = solo, 2 = two-player
final int SCREEN_HOME = 0;
final int SCREEN_CALIB = 1;
final int SCREEN_THERAPY = 2;
final int SCREEN_THERAPY_RESULTS = 3;
final int SCREEN_SHAPE = 4;
final int SCREEN_SHAPE_OVER = 5;
final int SCREEN_CONTROL = 6;

int screen = SCREEN_HOME;

float therapyMouseX = 0;
float therapyMouseY = 0;
boolean therapyMouseActive = false;
// Add after the gyro variables
boolean keyM_held = false;
boolean keyN_held = false;

final int CAM_W = 640;
final int CAM_H = 480;
final float WIN_SCALE = 1.5;
Capture cam;
int[] camPixels = null;
PImage previewFrame = null;
PreviewWindow previewWin;
Robot sysBot;
Serial serialPrimary;
Serial serialSecondary;

color primaryDefault = color(0, 240, 140);    // bright green (pre-calibrated)
color secondaryDefault = color(210, 90, 200); // magenta (pre-calibrated)
ColorTracker trackerA = new ColorTracker(primaryDefault);
ColorTracker trackerB = new ColorTracker(secondaryDefault);
float colorThreshold = 45;
float colorToleranceFactor = 1.02; // allow 2% slack to reduce jitter
float scanScale = 1.0;             // scan portion of camera (scaled, but keeps aspect below)
float screenAspect = 2560.0 / 1664.0; // MacBook Air M3 aspect

PVector calibPosA, calibPosB;
boolean prevMouseDown = false;
boolean justClicked = false;

// ---------- Therapy maze ----------
PGraphics mazeLayer;
PVector mazeStart, mazeGoal;
float mazePathWidth = 70;
String mazeDifficulty = "Easy";
boolean therapyRunning = false;
boolean therapyFinished = false;
int therapyStartMillis = 0;
int therapyEndMillis = 0;
TherapyStats statsA = new TherapyStats("Player A", primaryDefault);
TherapyStats statsB = new TherapyStats("Player B", secondaryDefault);

// ---------- Shape battle ----------
Tank player;
Tank bot;
ArrayList<Bullet> bullets = new ArrayList<Bullet>();
ArrayList<Obstacle> obstacles = new ArrayList<Obstacle>();
boolean keyW, keyA, keyS, keyD, keyQ, keyE, keyShoot;
boolean keyI, keyJ, keyK, keyL, keyU, keyO, keyShoot2;
boolean shapeGameOver = false;
String shapeWinner = "";
int lastPlayerShot = 0;
int lastBotShot = 0;

// ---------- Control screen (serial + mouse/keyboard) ----------
boolean controlScreenEnabled = true;
boolean ctrl_w, ctrl_a, ctrl_s, ctrl_d, ctrl_space;
boolean ctrl_up, ctrl_left, ctrl_down, ctrl_right, ctrl_enter;
boolean mouseHeld = false;
int fsrPrimary = 0, flexPrimary = 0;
int fsrSecondary = 0, flexSecondary = 0;
int lastFlexLogMs = 0;
int joyXPrimary = 0, joyYPrimary = 0;
int joyXSecondary = 0, joyYSecondary = 0;
int joyDeadZone = 120;
int mouseClickThreshold = 800;
int fsrSpaceThreshold = 800;
int fsrEnterThreshold = 800;
float gyroXPrimary = 0, gyroYPrimary = 0, gyroZPrimary = 0;
float gyroXSecondary = 0, gyroYSecondary = 0, gyroZSecondary = 0;
float gyroTurretDeadband = 10;   // dps before we rotate turret
float gyroTurretScale = 0.002;  // angle delta per frame per dps
float gyroTurretSpinStep = 0.05; // angle delta per frame when past deadband
float gyroZeroPrimaryZ = 0, gyroZeroSecondaryZ = 0;
boolean gyroZeroedPrimary = false, gyroZeroedSecondary = false;
float gyroZPrimaryAdj = 0, gyroZSecondaryAdj = 0;

void settings() {
  size(int(CAM_W * WIN_SCALE), int(CAM_H * WIN_SCALE));
}

void setup() {
  surface.setTitle("Calibration + Therapy + Shape Games");
  textFont(createFont("Arial", 16));
  setupCamera();
  startPreviewWindow();
  startTrackingThreads();
  setupRobot();
  setupSerial();
  gyroZeroedPrimary = gyroZeroedSecondary = false;
  gyroZeroPrimaryZ = gyroZeroSecondaryZ = 0;

  calibPosA = new PVector(width * 0.33, height * 0.5);
  calibPosB = new PVector(width * 0.67, height * 0.5);

  buildMaze();
  initShapeGame();
}

void setupCamera() {
  String[] cams = Capture.list();
  if (cams.length == 0) {
    println("No camera found.");
    return;
  }
  cam = new Capture(this, CAM_W, CAM_H, cams[0]);
  cam.start();
}

void startPreviewWindow() {
  previewWin = new PreviewWindow();
  String[] args = {"Camera Preview"};
  PApplet.runSketch(args, previewWin);
}

void startTrackingThreads() {
  trackerA.startThread();
  trackerB.startThread();
}

void draw() {
  justClicked = mousePressed && !prevMouseDown;
  prevMouseDown = mousePressed;

  background(16, 18, 26);
  updateCameraFrame();
  updateTracking();
  
  // Track mouse position for therapy mode
  if (screen == SCREEN_THERAPY) {
    therapyMouseX = mouseX;
    therapyMouseY = mouseY;
  }

  // --- FIX: ONLY CONTROL MOUSE ON CONTROL SCREEN ---
  if (screen == SCREEN_CONTROL) {
    controlMouseWithTracker();
  }

  switch (screen) {
    case SCREEN_HOME:
      drawHome();
      break;
    case SCREEN_CALIB:
      drawCalibration();
      break;
    case SCREEN_THERAPY:
      drawTherapy();
      break;
    case SCREEN_THERAPY_RESULTS:
      drawTherapyResults();
      break;
    case SCREEN_SHAPE:
      drawShapeGame();
      break;
    case SCREEN_SHAPE_OVER:
      drawShapeOver();
      break;
    case SCREEN_CONTROL:
      drawControlScreen();
      break;
  }
}

void mouseMoved() {
  if (screen == SCREEN_THERAPY) {
    therapyMouseX = mouseX;
    therapyMouseY = mouseY;
    therapyMouseActive = true;
  }
}

void mouseDragged() {
  if (screen == SCREEN_THERAPY) {
    therapyMouseX = mouseX;
    therapyMouseY = mouseY;
    therapyMouseActive = true;
  }
}


void updateCameraFrame() {
  if (cam == null) return;
  if (cam.available()) {
    cam.read();
    cam.loadPixels();
    camPixels = cam.pixels;
    previewFrame = cam.get();
    if (previewWin != null) {
      previewWin.setFrame(previewFrame, trackerA, trackerB, playerCount > 1);
    }
  }
}

void updateTracking() {
  if (camPixels == null) return;
  trackerA.setFrame(camPixels, cam.width, cam.height);
  trackerB.setFrame(camPixels, cam.width, cam.height);
}

// ------------------------------------------------------------
// Screens
// ------------------------------------------------------------
void drawHome() {
  drawBackdrop();
  drawBanner("Nearables / Wearables Lab", "Calibrate → choose players → pick a mode. Camera preview is in its own window.");
  //disableControlMode(); // safety when leaving control screen

  // Player count toggle on home
  float toggleY = 120;
  if (renderButton("1 Player (vs CPU)", 40, toggleY, 220, 36)) {
    playerCount = 1;
  }
  if (renderButton("2 Players (both humans)", 280, toggleY, 240, 36)) {
    playerCount = 2;
  }
  fill(180);
  textAlign(LEFT, CENTER);
  text("Current: " + (playerCount == 1 ? "Solo" : "Two players"), 540, toggleY + 18);

  // menu grid
  float cardW = (width - 100) / 2;
  float cardH = 90;
  drawDifficultyRow(40, 170);
  if (renderCard("Calibrate Colors", "Lock colors + choose 1P/2P", 40, 210, cardW, cardH)) screen = SCREEN_CALIB;
  if (renderCard("Therapy Maze", "Track dot through maze", 60 + cardW, 210, cardW, cardH)) startTherapyRun();
  if (renderCard("Shape Battle", "Tanks + bullets", 40, 210 + cardH + 20, cardW, cardH)) {
    resetShapeGame();
    screen = SCREEN_SHAPE;
  }
  if (renderCard("Serial Control", "Camera mouse + joystick keys", 60 + cardW, 210 + cardH + 20, cardW, cardH)) {
    screen = SCREEN_CONTROL;
  }
  if (renderCard("Quit", "Close app", 40, 210 + (cardH + 20) * 2, cardW, cardH)) exit();
}

void drawCalibration() {
  drawBackdrop();
  drawBanner("Calibration", "Set player count, place colors in circles, sample with 1/2.");
  drawCameraFull();

  fill(0, 0, 0, 150);
  noStroke();
  rect(20, 20, width - 40, 140, 12);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(20);
  text("Calibration", 30, 30);
  textSize(14);
  text("1) Choose player count. 2) Place colors in circles. 3) Press 1 for primary, 2 for secondary (only if 2 players). 4) ENTER/Continue to start. Camera preview is in its own window.", 30, 60, width - 60, 80);

  drawCalibCrosshair(calibPosA, primaryDefault);
  drawCalibCrosshair(calibPosB, secondaryDefault);

  // live tracked dots
  drawTrackedDot(trackerA, primaryDefault);
  drawTrackedDot(trackerB, secondaryDefault);

  // Color swatches + status
  drawColorSwatch("Primary", trackerA.target, trackerA.found, 30, height - 140);
  drawColorSwatch("Secondary", trackerB.target, trackerB.found && playerCount > 1, 230, height - 140);

  // Allow swapping which color is primary/secondary
  if (renderButton("Swap primary/secondary", width - 280, 170, 240, 36)) {
    flipPrimarySecondary();
  }

  float btnY = height - 70;
  if (renderButton("Back", 24, btnY, 160, 44)) {
    screen = SCREEN_HOME;
  }
  if (renderButton("Continue", 200, btnY, 180, 44)) {
    screen = SCREEN_HOME;
  }
}

// ============================================================
// MAZE THERAPY - COLLISION FIX
// ============================================================
// Replace your existing drawTherapy() and TherapyStats class with these:

void drawTherapy() {
  drawBackdrop();
  image(mazeLayer, 0, 0, width, height);
  drawTherapyHUD();
  
  String bannerText = playerCount > 1 ? "Both colors track together. Reach the gold goal." : "Keep the dot on the path. Reach the goal.";
  if (keyM_held) bannerText += " [MOUSE MODE - move mouse/trackpad]";
  drawBanner("Therapy Maze", bannerText);

  // Player A tracking - use mouse when M is held
  boolean useMouseA = keyM_held;
  PVector p = null;
  
  if (useMouseA) {
    // Use continuously tracked mouse position
    p = new PVector(therapyMouseX, therapyMouseY);
  } else if (trackerA.found && trackerA.smoothed != null) {
    // Use camera tracking
    p = trackerA.smoothed.copy();
  }
  
  if (p != null) {
    boolean onPath = isOnMaze(p);
    
    // IMPROVED: Check multiple points around the dot for camera tracking
    if (!useMouseA && trackerA.found) {
      float checkRadius = 12;
      boolean top = isOnMaze(new PVector(p.x, p.y - checkRadius));
      boolean bottom = isOnMaze(new PVector(p.x, p.y + checkRadius));
      boolean left = isOnMaze(new PVector(p.x - checkRadius, p.y));
      boolean right = isOnMaze(new PVector(p.x + checkRadius, p.y));
      
      int edgesOnPath = (top ? 1 : 0) + (bottom ? 1 : 0) + (left ? 1 : 0) + (right ? 1 : 0);
      onPath = onPath && edgesOnPath >= 2;
    }
    
    if (therapyRunning) {
      statsA.trackedFrames++;
      
      if (onPath) {
        statsA.onPath++;
        statsA.wasOffPath = false;
      } else {
        if (!statsA.wasOffPath) {
          statsA.collisions++;
          statsA.wasOffPath = true;
        }
      }
      
      statsA.refreshLive(therapyStartMillis);
      if (checkTherapyGoal(p)) statsA.reachedGoal = true;
    }

    noStroke();
    fill(onPath ? color(90, 255, 200) : color(255, 80, 120));
    ellipse(p.x, p.y, 24, 24);
    
    // Show indicator
    if (useMouseA) {
      fill(255, 255, 0, 150);
      textAlign(CENTER, CENTER);
      textSize(12);
      text("MOUSE", p.x, p.y - 20);
    }
  } else {
    fill(255, 60, 80);
    textAlign(CENTER, CENTER);
    textSize(16);
    text("Primary color not visible. Press and HOLD 'M' key, then move mouse/trackpad.", width * 0.5, height * 0.45);
  }

  // Player B tracking (only if enabled)
  if (playerCount > 1) {
    boolean useMouseB = keyN_held;
    PVector p2 = null;
    
    if (useMouseB) {
      p2 = new PVector(therapyMouseX, therapyMouseY);
    } else if (trackerB.found && trackerB.smoothed != null) {
      p2 = trackerB.smoothed.copy();
    }
    
    if (p2 != null) {
      boolean onPath2 = isOnMaze(p2);
      
      if (!useMouseB && trackerB.found) {
        float checkRadius = 12;
        boolean top = isOnMaze(new PVector(p2.x, p2.y - checkRadius));
        boolean bottom = isOnMaze(new PVector(p2.x, p2.y + checkRadius));
        boolean left = isOnMaze(new PVector(p2.x - checkRadius, p2.y));
        boolean right = isOnMaze(new PVector(p2.x + checkRadius, p2.y));
        
        int edgesOnPath = (top ? 1 : 0) + (bottom ? 1 : 0) + (left ? 1 : 0) + (right ? 1 : 0);
        onPath2 = onPath2 && edgesOnPath >= 2;
      }
      
      if (therapyRunning) {
        statsB.trackedFrames++;
        
        if (onPath2) {
          statsB.onPath++;
          statsB.wasOffPath = false;
        } else {
          if (!statsB.wasOffPath) {
            statsB.collisions++;
            statsB.wasOffPath = true;
          }
        }
        
        statsB.refreshLive(therapyStartMillis);
        if (checkTherapyGoal(p2)) statsB.reachedGoal = true;
      }

      noStroke();
      fill(onPath2 ? color(140, 255, 200) : color(255, 210, 120));
      ellipse(p2.x, p2.y, 24, 24);
      
      if (useMouseB) {
        fill(255, 100, 255, 150);
        textAlign(CENTER, CENTER);
        textSize(12);
        text("MOUSE", p2.x, p2.y - 20);
      }
    } else {
      fill(255, 210, 120);
      textAlign(CENTER, CENTER);
      textSize(16);
      text("Secondary color not visible. Press and HOLD 'N' key, then move mouse/trackpad.", width * 0.5, height * 0.55);
    }
  }

  // auto-finish if goal reached
  if (therapyRunning) {
    if (playerCount > 1) {
      if (statsA.reachedGoal && statsB.reachedGoal) finishTherapy();
    } else if (statsA.reachedGoal) {
      finishTherapy();
    }
  }

  // Controls
  float btnY = height - 70;
  if (renderButton("Restart", 24, btnY, 140, 44)) {
    startTherapyRun();
  }
  if (renderButton("Back", 180, btnY, 140, 44)) {
    screen = SCREEN_HOME;
  }
  if (renderButton("Finish", 336, btnY, 140, 44)) {
    finishTherapy();
  }
}

void drawTherapyResults() {
  drawBackdrop();
  image(mazeLayer, 0, 0, width, height);
  fill(0, 0, 0, 180);
  noStroke();
  rect(40, 80, width - 80, height - 160, 14);

  fill(255);
  textAlign(LEFT, TOP);
  textSize(26);
  text("Session summary (" + playerCount + " player" + (playerCount > 1 ? "s" : "") + ")", 60, 100);
  textSize(16);
  text("Difficulty: " + mazeDifficulty, width - 220, 108);

  textSize(18);
  float y = 150;
  text(statsA.label + " — Time: " + nf(statsA.timeSec, 0, 2) + " s", 60, y); y += 24;
  text("Accuracy: " + nf(statsA.accuracy * 100, 0, 1) + "%   Collisions: " + statsA.collisions, 60, y); y += 24;
  textSize(16);
  text("Fact: " + statsA.fact, 60, y, width - 120, 120); y += 110;

  if (playerCount > 1) {
    textSize(18);
    text(statsB.label + " — Time: " + nf(statsB.timeSec, 0, 2) + " s", 60, y); y += 24;
    text("Accuracy: " + nf(statsB.accuracy * 100, 0, 1) + "%   Collisions: " + statsB.collisions, 60, y); y += 24;
    textSize(16);
    text("Fact: " + statsB.fact, 60, y, width - 120, 120);
  }

  float btnY = height - 80;
  if (renderButton("Run again", 70, btnY, 200, 48)) {
    startTherapyRun();
  }
  if (renderButton("Back to menu", 300, btnY, 220, 48)) {
    screen = SCREEN_HOME;
  }
}

void drawShapeGame() {
  drawBackdrop();
  drawBanner("Shape Battle", playerCount > 1 ? "P1 vs P2: WASD/QE/SPACE vs IJKL/UO/ENTER" : "P1 vs CPU: WASD/QE/SPACE");
  drawShapeMap();

  updateShapeWorld();

  drawBullets();

  player.draw();
  bot.draw();
  drawShapeHUD();

  float btnY = height - 70;
  if (renderButton("Restart", 24, btnY, 140, 44)) {
    resetShapeGame();
  }
  if (renderButton("Back", 180, btnY, 140, 44)) {
    screen = SCREEN_HOME;
  }
}

void drawShapeOver() {
  // render static world without advancing state
  drawBackdrop();
  drawShapeMap();
  drawBullets();
  player.draw();
  bot.draw();
  drawShapeHUD();

  fill(0, 0, 0, 190);
  noStroke();
  rect(0, 0, width, height);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(28);
  text(shapeWinner + " wins!", width * 0.5, height * 0.4);
  textSize(16);
  text("Press restart to play again or back to return to the menu.", width * 0.5, height * 0.48);

  float btnY = height * 0.55;
  if (renderButton("Restart", width * 0.5 - 160, btnY, 160, 44)) {
    resetShapeGame();
    screen = SCREEN_SHAPE;
  }
  if (renderButton("Back", width * 0.5 + 10, btnY, 160, 44)) {
    screen = SCREEN_HOME;
  }
}

void drawControlScreen() {
  drawBackdrop();
  drawBanner("Serial Control", "Primary device (primary color) drives mouse + WASD/SPACE. Secondary device drives arrows/ENTER only. Joy remap: X>800→W, X<250→S, Y>800→D, Y<250→A.");

  fill(0, 0, 0, 140);
  noStroke();
  rect(40, 120, width - 80, 160, 12);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(16);
  String serialStatus = "P:" + (serialPrimary != null ? "ok" : "none") + "  S:" + (serialSecondary != null ? "ok" : "none");
  text("Status: " + (controlScreenEnabled ? "ENABLED" : "DISABLED") + "  |  Serial: " + serialStatus, 60, 140);
  textSize(14);
  text("Primary: mouse + WASD, Flex > " + mouseClickThreshold + " = mouse click, FSR > " + fsrSpaceThreshold + " = SPACE. Secondary: arrows, FSR > " + fsrEnterThreshold + " = ENTER; flex also counts for click if devices swap. Hit STOP anytime.", 60, 168, width - 120, 60);

  if (renderButton(controlScreenEnabled ? "STOP (disable input)" : "START (enable input)", width * 0.5 - 140, 320, 280, 70)) {
    controlScreenEnabled = !controlScreenEnabled;
    if (!controlScreenEnabled) {
      releaseControlKeys();
      releaseMouse();
    } else {
      setupSerial();
    }
  }

  // live values
  fill(200);
  textAlign(LEFT, TOP);
  text("Primary → FSR: " + fsrPrimary + "   Flex: " + flexPrimary + "   joyX: " + joyXPrimary + "   joyY: " + joyYPrimary + "   gyroZ(adj): " + nf(gyroZPrimaryAdj, 0, 1), 60, 410);
  text("Secondary → FSR: " + fsrSecondary + "   joyX: " + joyXSecondary + "   joyY: " + joyYSecondary + "   gyroZ(adj): " + nf(gyroZSecondaryAdj, 0, 1), 60, 436);

  // Back button
  if (renderButton("Back", 40, height - 70, 140, 44)) {
    screen = SCREEN_HOME;
  }
}

void updateShapeWorld() {
  handlePlayer();
  handleBot();
  updateBullets();
}

// ------------------------------------------------------------
// Calibration helpers
// ------------------------------------------------------------
void drawCameraFull() {
  if (cam == null) return;
  pushMatrix();
  scale(-1, 1);
  image(cam, -width, 0, width, height);
  popMatrix();
}

void drawMiniCameraPreview(float x, float y, float w, float h) {
  if (cam == null) return;
  pushMatrix();
  translate(x + w, y);
  scale(-1, 1);
  image(cam, 0, 0, w, h);
  popMatrix();
  stroke(255, 120);
  noFill();
  rect(x, y, w, h);
}

void drawTrackerDots(float x, float y, float w, float h) {
  if (cam == null) return;
  float sx = w / float(cam.width);
  float sy = h / float(cam.height);

  if (trackerA.found && trackerA.camPos != null) {
    float dx = x + (cam.width - trackerA.camPos.x) * sx;
    float dy = y + trackerA.camPos.y * sy;
    noStroke();
    fill(primaryDefault);
    ellipse(dx, dy, 12, 12);
  }
  if (trackerB.found && trackerB.camPos != null) {
    float dx = x + (cam.width - trackerB.camPos.x) * sx;
    float dy = y + trackerB.camPos.y * sy;
    noStroke();
    fill(secondaryDefault);
    ellipse(dx, dy, 12, 12);
  }
}

void drawCalibCrosshair(PVector pos, color c) {
  strokeWeight(2);
  stroke(c);
  noFill();
  ellipse(pos.x, pos.y, 38, 38);
  line(pos.x - 16, pos.y, pos.x + 16, pos.y);
  line(pos.x, pos.y - 16, pos.x, pos.y + 16);
}

void drawTrackedDot(ColorTracker t, color c) {
  if (!t.found) return;
  PVector p = t.smoothed;
  noStroke();
  fill(c);
  ellipse(p.x, p.y, 22, 22);
}

// ------------------------------------------------------------
// Therapy logic
// ------------------------------------------------------------
void buildMaze() {
  mazeLayer = createGraphics(width, height);
  updateMazeSettings();
  mazeStart = new PVector(70, height - 70);
  mazeGoal = new PVector(width - 70, 70);

  ArrayList<PVector> pts = generatePathAnchors();
  pts.add(0, mazeStart);
  pts.add(mazeGoal);

  mazeLayer.beginDraw();
  mazeLayer.background(12, 14, 22);
  mazeLayer.stroke(55, 140, 255);
  mazeLayer.strokeWeight(mazePathWidth);
  mazeLayer.noFill();
  for (int i = 0; i < pts.size() - 1; i++) {
    PVector a = pts.get(i);
    PVector b = pts.get(i + 1);
    mazeLayer.line(a.x, a.y, b.x, b.y);
  }
  mazeLayer.noStroke();
  mazeLayer.fill(50, 220, 150);
  mazeLayer.ellipse(mazeStart.x, mazeStart.y, mazePathWidth, mazePathWidth);
  mazeLayer.fill(255, 200, 80);
  mazeLayer.ellipse(mazeGoal.x, mazeGoal.y, mazePathWidth * 0.9, mazePathWidth * 0.9);
  mazeLayer.endDraw();
  mazeLayer.loadPixels();
}

boolean isOnMaze(PVector p) {
  int x = constrain(int(p.x), 0, mazeLayer.width-1);
  int y = constrain(int(p.y), 0, mazeLayer.height-1);

  int col = mazeLayer.pixels[y * mazeLayer.width + x];
  return brightness(col) > 25;
}

void startTherapyRun() {
  buildMaze(); // new randomized maze each time, respects difficulty
  therapyRunning = true;
  therapyFinished = false;
  statsA.reset();
  statsB.reset();
  therapyStartMillis = millis();
  screen = SCREEN_THERAPY;
}

void finishTherapy() {
  therapyRunning = false;
  therapyFinished = true;
  therapyEndMillis = millis();

  statsA.finish(therapyStartMillis, therapyEndMillis);
  if (playerCount > 1) {
    statsB.finish(therapyStartMillis, therapyEndMillis);
  }
  screen = SCREEN_THERAPY_RESULTS;
}

void updateMazeSettings() {
  if (mazeDifficulty.equals("Easy")) {
    mazePathWidth = 95;
  } else if (mazeDifficulty.equals("Medium")) {
    mazePathWidth = 70;
  } else {
    mazePathWidth = 50;
  }
}

ArrayList<PVector> generatePathAnchors() {
  ArrayList<PVector> pts = new ArrayList<PVector>();
  int segments;
  float jitter;
  if (mazeDifficulty.equals("Easy")) {
    segments = 4;
    jitter = height * 0.08;
  } else if (mazeDifficulty.equals("Medium")) {
    segments = 6;
    jitter = height * 0.14;
  } else {
    segments = 9;
    jitter = height * 0.22;
  }

  float usableW = width - 140;
  float dx = usableW / (segments + 1);
  float baseY1 = height * 0.75;
  float baseY2 = height * 0.25;

  for (int i = 1; i <= segments; i++) {
    float x = 70 + dx * i;
    float t = i / float(segments + 1);
    float baseY = lerp(baseY1, baseY2, t);
    float y = baseY + random(-jitter, jitter);
    y = constrain(y, 60, height - 60);
    pts.add(new PVector(x, y));
  }

  if (mazeDifficulty.equals("Hard")) {
    // add a couple of sharp turns to make it tricky
    for (int i = 0; i < 2; i++) {
      float x = random(width * 0.3, width * 0.7);
      float y = random(height * 0.25, height * 0.75);
      pts.add(new PVector(x, y));
    }
    pts.sort(new java.util.Comparator<PVector>() {
      public int compare(PVector a, PVector b) {
        return (a.x < b.x) ? -1 : 1;
      }
    });
  }

  return pts;
}

boolean checkTherapyGoal(PVector p) {
  if (p == null) return false;
  return p.dist(mazeGoal) < mazePathWidth * 0.4;
}

void drawTherapyHUD() {
  fill(0, 0, 0, 140);
  noStroke();
  rect(0, 0, width, 70);
  fill(255);
  textAlign(LEFT, CENTER);
  textSize(16);
  float elapsed = (therapyRunning ? (millis() - therapyStartMillis) / 1000.0 : statsA.timeSec);
  text("Time: " + nf(elapsed, 0, 2) + " s", 20, 35);
  text("P1 acc: " + nf(statsA.accuracy * 100, 0, 1) + "% | col: " + statsA.collisions, 170, 35);
  if (playerCount > 1) {
    text("P2 acc: " + nf(statsB.accuracy * 100, 0, 1) + "% | col: " + statsB.collisions, 380, 35);
  }
  text("Difficulty: " + mazeDifficulty + " | Goal: reach the gold circle", width - 300, 35);
}

String pickTherapyFact(float accuracy, float timeSec) {
  String[] fastFacts = {
    "Smooth, fast movement hints at strong motor planning.",
    "Speed plus accuracy means great hand-eye coordination.",
    "Staying on-path at pace trains proprioception and focus."
  };
  String[] steadyFacts = {
    "Precise path-following trains fine motor control.",
    "Holding within the lane builds steadiness and control.",
    "Consistent accuracy suggests reliable calibration."
  };
  String[] catchupFacts = {
    "Most collisions happen on turns; try pausing before pivoting.",
    "Wider arcs can reduce drift if the dot wobbles.",
    "Recalibrate colors if the dot feels jumpy."
  };

  if (accuracy > 0.8 && timeSec < 25) {
    return fastFacts[(int)random(fastFacts.length)];
  } else if (accuracy > 0.6) {
    return steadyFacts[(int)random(steadyFacts.length)];
  }
  return catchupFacts[(int)random(catchupFacts.length)];
}

// ------------------------------------------------------------
// Shape battle logic
// ------------------------------------------------------------
void initShapeGame() {
  obstacles.clear();
  obstacles.add(new Obstacle(width * 0.35, height * 0.25, 120, 40));
  obstacles.add(new Obstacle(width * 0.15, height * 0.55, 160, 50));
  obstacles.add(new Obstacle(width * 0.6, height * 0.35, 200, 40));
  obstacles.add(new Obstacle(width * 0.55, height * 0.7, 160, 50));
  obstacles.add(new Obstacle(width * 0.2, height * 0.8, 120, 35));

  resetShapeGame();
}

void resetShapeGame() {
  bullets.clear();
  // ADD shape parameter (0 for square, 1 for pentagon)
  player = new Tank(new PVector(width * 0.2, height * 0.5), color(90, 180, 255), true, 0);
  bot = new Tank(new PVector(width * 0.8, height * 0.5), color(255, 180, 90), false, 1);
  player.hits = bot.hits = 0;
  player.maxLives = bot.maxLives = 5; // ADD this line
  shapeGameOver = false;
  shapeWinner = "";
}

void drawShapeMap() {
  noStroke();
  fill(20, 26, 36);
  rect(0, 0, width, height);

  fill(38, 46, 68);
  for (Obstacle o : obstacles) {
    o.draw();
  }
}

void handlePlayer() {
  if (shapeGameOver) return;
  PVector move = new PVector();
  if (keyW) move.y -= 1;
  if (keyS) move.y += 1;
  if (keyA) move.x -= 1;
  if (keyD) move.x += 1;
  player.move(move, obstacles);

  if (keyQ) player.turretAngle -= 0.04;
  if (keyE) player.turretAngle += 0.04;
  if (gyroZPrimaryAdj > gyroTurretDeadband) {
    player.turretAngle += gyroTurretSpinStep; // CW when tilted right
  } else if (gyroZPrimaryAdj < -gyroTurretDeadband) {
    player.turretAngle -= gyroTurretSpinStep; // CCW when tilted left
  }

  if (keyShoot && millis() - lastPlayerShot > 200) {
    shoot(player);
    lastPlayerShot = millis();
  }
}

void handleBot() {
  if (shapeGameOver) return;
  if (playerCount > 1) {
    // second human player controls
    PVector move2 = new PVector();
    if (keyI) move2.y -= 1;
    if (keyK) move2.y += 1;
    if (keyJ) move2.x -= 1;
    if (keyL) move2.x += 1;
    bot.move(move2, obstacles);

    if (keyU) bot.turretAngle -= 0.04;
    if (keyO) bot.turretAngle += 0.04;
    if (gyroZSecondaryAdj > gyroTurretDeadband) {
      bot.turretAngle += gyroTurretSpinStep; // CW when tilted right
    } else if (gyroZSecondaryAdj < -gyroTurretDeadband) {
      bot.turretAngle -= gyroTurretSpinStep; // CCW when tilted left
    }
    if (keyShoot2 && millis() - lastBotShot > 200) {
      shoot(bot);
      lastBotShot = millis();
    }
  } else {
    // AI bot
    PVector toPlayer = PVector.sub(player.pos, bot.pos);
    PVector dir = toPlayer.copy();
    if (dir.magSq() > 0.001) {
      dir.normalize();
    } else {
      dir.set(0, 0);
    }
    bot.move(dir, obstacles);

    float targetAngle = atan2(toPlayer.y, toPlayer.x);
    bot.turretAngle = lerpAngle(bot.turretAngle, targetAngle, 0.08);

    if (millis() - lastBotShot > 600) {
      shoot(bot);
      lastBotShot = millis();
    }
  }
}

float lerpAngle(float a, float b, float amt) {
  float diff = atan2(sin(b - a), cos(b - a));
  return a + diff * amt;
}

void shoot(Tank t) {
  PVector dir = new PVector(cos(t.turretAngle), sin(t.turretAngle));
  PVector pos = PVector.add(t.pos, PVector.mult(dir, t.radius + 6));
  PVector vel = PVector.mult(dir, 8);
  bullets.add(new Bullet(pos, vel, t));
}

void updateBullets() {
  for (Bullet b : bullets) {
    b.update();
    // obstacle collisions
    for (Obstacle o : obstacles) {
      if (o.containsPoint(b.pos.x, b.pos.y)) {
        b.expired = true;
      }
    }
    // player hit
    if (!b.expired && b.owner != player && b.hitsTank(player)) {
      player.takeDamage(); // CHANGED from player.hits++
      b.expired = true;
      checkShapeGameOver();
    }
    // bot hit
    if (!b.expired && b.owner != bot && b.hitsTank(bot)) {
      bot.takeDamage(); // CHANGED from bot.hits++
      b.expired = true;
      checkShapeGameOver();
    }
  }

  for (int i = bullets.size() - 1; i >= 0; i--) {
    if (bullets.get(i).expired) bullets.remove(i);
  }
}

void drawBullets() {
  // CHANGED to use bullet's own draw method instead of ellipse
  for (Bullet b : bullets) {
    b.draw();
  }
}

void checkShapeGameOver() {
  if (player.hits >= player.maxLives) { // CHANGED from playerMaxHits
    shapeGameOver = true;
    shapeWinner = (playerCount > 1) ? "Player 2 (Pentagon)" : "Bot (Pentagon)"; // ADDED shape names
    screen = SCREEN_SHAPE_OVER;
  } else if (bot.hits >= bot.maxLives) { // CHANGED from botMaxHits
    shapeGameOver = true;
    shapeWinner = "Player 1 (Square)"; // ADDED shape name
    screen = SCREEN_SHAPE_OVER;
  }
}

void drawShapeHUD() {
  fill(0, 0, 0, 150);
  noStroke();
  rect(0, 0, width, 60);
  fill(255);
  textAlign(LEFT, CENTER);
  textSize(16);
  // CHANGED to show lives remaining instead of hits taken
  text("P1 (Square) lives: " + (player.maxLives - player.hits) + "/" + player.maxLives, 20, 30);
  text((playerCount > 1 ? "P2" : "CPU") + " (Pentagon) lives: " + (bot.maxLives - bot.hits) + "/" + bot.maxLives, 240, 30);
  text("Shrinks with each hit! | P1: WASD/QE/SPACE | P2: IJKL/UO/ENTER", 520, 30);
}

// ------------------------------------------------------------
// UI helpers
// ------------------------------------------------------------
void drawBackdrop() {
  background(16, 18, 26);
  noStroke();
  for (int i = 0; i < 10; i++) {
    float alpha = map(i, 0, 9, 40, 5);
    fill(30, 36, 60, alpha);
    rect(0, i * (height / 10.0), width, height / 10.0);
  }
}

void drawBanner(String title, String subtitle) {
  noStroke();
  fill(25, 30, 50, 220);
  rect(20, 14, width - 40, 64, 14);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(22);
  text(title, 36, 24);
  fill(200);
  textSize(14);
  text(subtitle, 36, 50, width - 72, 40);
}

// ------------------------------------------------------------
// Control helpers
// ------------------------------------------------------------
void setupRobot() {
  try {
    sysBot = new Robot();
  }
  catch (Exception e) {
    println("Robot init failed: " + e.getMessage());
  }
}

void setupSerial() {
  String[] ports = Serial.list();
  if (ports.length == 0) {
    println("No serial ports found.");
    return;
  }

  // Primary uses the last port
  if (serialPrimary == null) {
    String primaryPort = ports[ports.length - 1];
    try {
      println("Opening PRIMARY serial on " + primaryPort + " @115200");
      serialPrimary = new Serial(this, primaryPort, 115200);
      serialPrimary.clear();
    }
    catch (Exception e) {
      println("Primary serial init failed: " + e.getMessage());
      serialPrimary = null;
    }
  }

  // Small delay to avoid driver contention when opening back-to-back
  delay(2000);

  // Secondary uses the second-to-last port (if available)
  if (ports.length >= 2 && serialSecondary == null) {
    String secondaryPort = ports[ports.length - 2];
    try {
      println("Opening SECONDARY serial on " + secondaryPort + " @115200");
      serialSecondary = new Serial(this, secondaryPort, 115200);
      serialSecondary.clear();
    }
    catch (Exception e) {
      println("Secondary serial init failed: " + e.getMessage());
      serialSecondary = null;
    }
  }
}

void serialEvent(Serial port) {
  String line = port.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  String[] parts = split(line, ',');
  if (parts.length < 11) return;

  if (port == serialPrimary) {
    handlePrimaryPacket(parts);
  } else if (port == serialSecondary) {
    handleSecondaryPacket(parts);
  }
}

void handlePrimaryPacket(String[] parts) {
  try {
    fsrPrimary = int(parts[0].trim());
    flexPrimary = int(parts[1].trim());
    gyroXPrimary = float(parts[5].trim());
    gyroYPrimary = float(parts[6].trim());
    gyroZPrimary = float(parts[7].trim());
    if (!gyroZeroedPrimary) {
      gyroZeroPrimaryZ = gyroZPrimary;
      gyroZeroedPrimary = true;
    }
    gyroZPrimaryAdj = gyroZPrimary - gyroZeroPrimaryZ;
    joyXPrimary = int(parts[8].trim());
    joyYPrimary = int(parts[9].trim());
  }
  catch (Exception e) {
    return;
  }

  if (!controlScreenEnabled || sysBot == null) return;
  handlePrimaryJoystickKeys();
  handlePrimarySpace();
  handlePrimaryMouseClick();
}

void handleSecondaryPacket(String[] parts) {
  try {
    fsrSecondary = int(parts[0].trim());
    flexSecondary = int(parts[1].trim());
    gyroXSecondary = float(parts[5].trim());
    gyroYSecondary = float(parts[6].trim());
    gyroZSecondary = float(parts[7].trim());
    if (!gyroZeroedSecondary) {
      gyroZeroSecondaryZ = gyroZSecondary;
      gyroZeroedSecondary = true;
    }
    gyroZSecondaryAdj = gyroZSecondary - gyroZeroSecondaryZ;
    joyXSecondary = int(parts[8].trim());
    joyYSecondary = int(parts[9].trim());
  }
  catch (Exception e) {
    return;
  }

  if (!controlScreenEnabled || sysBot == null) return;
  handleSecondaryJoystickKeys();
  handleSecondaryEnter();
}

void handlePrimaryJoystickKeys() {
  boolean joyUp = joyYPrimary > 800;
  boolean joyDown = joyYPrimary < 250;
  boolean joyRight = joyXPrimary > 800;
  boolean joyLeft = joyXPrimary < 250;

  // Remap: A movement drives W key; W movement drives D key; swap S/A outputs
  boolean wNew = joyRight;
  boolean sNew = joyLeft;
  boolean aNew = joyDown;
  boolean dNew = joyUp;

  updateKey(ctrl_w, wNew, java.awt.event.KeyEvent.VK_W);
  updateKey(ctrl_s, sNew, java.awt.event.KeyEvent.VK_S);
  updateKey(ctrl_a, aNew, java.awt.event.KeyEvent.VK_A);
  updateKey(ctrl_d, dNew, java.awt.event.KeyEvent.VK_D);

  ctrl_w = wNew;
  ctrl_s = sNew;
  ctrl_a = aNew;
  ctrl_d = dNew;
}

void handleSecondaryJoystickKeys() {
  boolean joyUp = joyYSecondary > 800;
  boolean joyDown = joyYSecondary < 250;
  boolean joyRight = joyXSecondary > 800;
  boolean joyLeft = joyXSecondary < 250;

  // Same remap as primary, but drive arrow keys
  boolean upNew = joyRight;
  boolean downNew = joyLeft;
  boolean leftNew = joyDown;
  boolean rightNew = joyUp;

  updateKey(ctrl_up, upNew, java.awt.event.KeyEvent.VK_UP);
  updateKey(ctrl_down, downNew, java.awt.event.KeyEvent.VK_DOWN);
  updateKey(ctrl_left, leftNew, java.awt.event.KeyEvent.VK_LEFT);
  updateKey(ctrl_right, rightNew, java.awt.event.KeyEvent.VK_RIGHT);

  ctrl_up = upNew;
  ctrl_down = downNew;
  ctrl_left = leftNew;
  ctrl_right = rightNew;
}

void updateKey(boolean current, boolean desired, int keyCode) {
  if (sysBot == null) return;
  if (desired && !current) {
    sysBot.keyPress(keyCode);
  } else if (!desired && current) {
    sysBot.keyRelease(keyCode);
  }
}

void handlePrimaryMouseClick() {
  if (sysBot == null) return;
  // Allow either device's flex to click, so swapping devices still works
  boolean shouldHold = (flexPrimary > mouseClickThreshold) || (flexSecondary > mouseClickThreshold);
  if (shouldHold && !mouseHeld) {
    sysBot.mousePress(InputEvent.BUTTON1_DOWN_MASK);
    mouseHeld = true;
  } else if (!shouldHold && mouseHeld) {
    sysBot.mouseRelease(InputEvent.BUTTON1_DOWN_MASK);
    mouseHeld = false;
  }
}

void handlePrimarySpace() {
  boolean spaceNew = fsrPrimary > fsrSpaceThreshold;
  updateKey(ctrl_space, spaceNew, java.awt.event.KeyEvent.VK_SPACE);
  ctrl_space = spaceNew;
}

void handleSecondaryEnter() {
  boolean enterNew = fsrSecondary > fsrEnterThreshold;
  updateKey(ctrl_enter, enterNew, java.awt.event.KeyEvent.VK_ENTER);
  ctrl_enter = enterNew;
}

void controlMouseWithTracker() {
  if (!controlScreenEnabled || sysBot == null) return;
  if (!trackerA.found || trackerA.smoothed == null) return;
  float nx = constrain(trackerA.smoothed.x / float(width), 0, 1);
  float ny = constrain(trackerA.smoothed.y / float(height), 0, 1);
  int sx = int(nx * displayWidth);
  int sy = int(ny * displayHeight);
  sysBot.mouseMove(sx, sy);
}

void disableControlMode() {
  if (controlScreenEnabled) {
    controlScreenEnabled = false;
    releaseControlKeys();
    releaseMouse();
  }
}

void releaseControlKeys() {
  if (sysBot == null) return;
  int[] keys = {
    java.awt.event.KeyEvent.VK_W,
    java.awt.event.KeyEvent.VK_A,
    java.awt.event.KeyEvent.VK_S,
    java.awt.event.KeyEvent.VK_D,
    java.awt.event.KeyEvent.VK_SPACE,
    java.awt.event.KeyEvent.VK_UP,
    java.awt.event.KeyEvent.VK_DOWN,
    java.awt.event.KeyEvent.VK_LEFT,
    java.awt.event.KeyEvent.VK_RIGHT,
    java.awt.event.KeyEvent.VK_ENTER
  };
  for (int k : keys) sysBot.keyRelease(k);
  ctrl_w = ctrl_a = ctrl_s = ctrl_d = ctrl_space = false;
  ctrl_up = ctrl_down = ctrl_left = ctrl_right = ctrl_enter = false;
}

void releaseMouse() {
  if (sysBot == null) return;
  sysBot.mouseRelease(InputEvent.BUTTON1_DOWN_MASK);
  mouseHeld = false;
}

boolean renderButton(String label, float x, float y, float w, float h) {
  boolean hover = mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  int bg1 = hover ? color(80, 140, 255) : color(60, 80, 130);
  int bg2 = hover ? color(60, 100, 200) : color(40, 60, 100);
  noStroke();
  beginShape();
  fill(bg1);
  vertex(x, y);
  vertex(x + w, y);
  fill(bg2);
  vertex(x + w, y + h);
  vertex(x, y + h);
  endShape(CLOSE);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(16);
  text(label, x + w / 2, y + h / 2);
  return hover && justClicked;
}

boolean renderCard(String title, String subtitle, float x, float y, float w, float h) {
  boolean hover = mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  int bg = hover ? color(80, 120, 210) : color(50, 70, 120);
  noStroke();
  fill(bg);
  rect(x, y, w, h, 14);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(18);
  text(title, x + 16, y + 14);
  textSize(13);
  fill(210);
  text(subtitle, x + 16, y + 38);
  return hover && justClicked;
}

void drawDifficultyRow(float x, float y) {
  textAlign(LEFT, CENTER);
  textSize(14);
  fill(200);
  text("Maze difficulty:", x, y + 12);
  float bx = x + 140;
  renderDifficultyButton("Easy", bx, y, 80, 32);
  renderDifficultyButton("Medium", bx + 90, y, 100, 32);
  renderDifficultyButton("Hard", bx + 200, y, 80, 32);
}

void renderDifficultyButton(String label, float x, float y, float w, float h) {
  boolean hover = mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  boolean active = mazeDifficulty.equals(label);
  int bg = active ? color(90, 180, 120) : (hover ? color(80, 110, 160) : color(50, 70, 110));
  noStroke();
  fill(bg);
  rect(x, y, w, h, 10);
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(14);
  text(label, x + w / 2, y + h / 2);
  if (hover && justClicked) {
    mazeDifficulty = label;
    updateMazeSettings();
  }
}

void drawColorSwatch(String label, color c, boolean seen, float x, float y) {
  pushStyle();
  stroke(255, 120);
  fill(c);
  rect(x, y, 120, 40, 8);
  fill(255);
  textAlign(LEFT, CENTER);
  text(label, x + 130, y + 10);
  fill(seen ? color(90, 220, 150) : color(255, 140, 100));
  text(seen ? "Seen" : "Not seen", x + 130, y + 28);
  popStyle();
}

void flipPrimarySecondary() {
  color tmpTarget = trackerA.target;
  trackerA.setColor(trackerB.target);
  trackerB.setColor(tmpTarget);

  color tmpDefault = primaryDefault;
  primaryDefault = secondaryDefault;
  secondaryDefault = tmpDefault;

  statsA.dotColor = primaryDefault;
  statsB.dotColor = secondaryDefault;

  println("Flipped colors. Primary now: " + rgbString(trackerA.target) + " | Secondary: " + rgbString(trackerB.target));
}

// ------------------------------------------------------------
// Input
// ------------------------------------------------------------
void keyPressed() {
  if (key == 'w' || key == 'W') keyW = true;
  if (key == 'a' || key == 'A') keyA = true;
  if (key == 's' || key == 'S') keyS = true;
  if (key == 'd' || key == 'D') keyD = true;
  if (key == 'q' || key == 'Q') keyQ = true;
  if (key == 'e' || key == 'E') keyE = true;
  if (key == ' ') keyShoot = true;
  if (key == 'i' || key == 'I') keyI = true;
  if (key == 'j' || key == 'J') keyJ = true;
  if (key == 'k' || key == 'K') keyK = true;
  if (key == 'l' || key == 'L') keyL = true;
  if (key == 'u' || key == 'U') keyU = true;
  if (key == 'o' || key == 'O') keyO = true;
  if (keyCode == ENTER || keyCode == RETURN) keyShoot2 = true;
  if (keyCode == UP) keyI = true;
  if (keyCode == DOWN) keyK = true;
  if (keyCode == LEFT) keyJ = true;
  if (keyCode == RIGHT) keyL = true;
  
  // ADD THESE LINES for mouse control
  if (key == 'm' || key == 'M') keyM_held = true;
  if (key == 'n' || key == 'N') keyN_held = true;

  // calibration hotkeys
  if (screen == SCREEN_CALIB && camPixels != null) {
    if (key == '1') {
      trackerA.setColor(sampleColorAt(calibPosA));
      println("Primary calibrated:", red(trackerA.target), green(trackerA.target), blue(trackerA.target));
    } else if (key == '2') {
      trackerB.setColor(sampleColorAt(calibPosB));
      println("Secondary calibrated:", red(trackerB.target), green(trackerB.target), blue(trackerB.target));
    } else if (keyCode == ENTER || keyCode == RETURN) {
      screen = SCREEN_HOME;
    }
  }
}

void keyReleased() {
  if (key == 'w' || key == 'W') keyW = false;
  if (key == 'a' || key == 'A') keyA = false;
  if (key == 's' || key == 'S') keyS = false;
  if (key == 'd' || key == 'D') keyD = false;
  if (key == 'q' || key == 'Q') keyQ = false;
  if (key == 'e' || key == 'E') keyE = false;
  if (key == ' ') keyShoot = false;
  if (key == 'i' || key == 'I') keyI = false;
  if (key == 'j' || key == 'J') keyJ = false;
  if (key == 'k' || key == 'K') keyK = false;
  if (key == 'l' || key == 'L') keyL = false;
  if (key == 'u' || key == 'U') keyU = false;
  if (key == 'o' || key == 'O') keyO = false;
  if (keyCode == ENTER || keyCode == RETURN) keyShoot2 = false;
  if (keyCode == UP) keyI = false;
  if (keyCode == DOWN) keyK = false;
  if (keyCode == LEFT) keyJ = false;
  if (keyCode == RIGHT) keyL = false;
  
  // ADD THESE LINES for mouse control
  if (key == 'm' || key == 'M') keyM_held = false;
  if (key == 'n' || key == 'N') keyN_held = false;
}

color sampleColorAt(PVector screenPos) {
  if (camPixels == null) return color(255, 0, 0);
  int sx = int(map(screenPos.x, 0, width, cam.width, 0)); // mirror
  int sy = int(map(screenPos.y, 0, height, 0, cam.height));
  sx = constrain(sx, 0, cam.width - 1);
  sy = constrain(sy, 0, cam.height - 1);
  return camPixels[sy * cam.width + sx];
}

// ------------------------------------------------------------
// Utility classes
// ------------------------------------------------------------
class TherapyStats {
  String label;
  color dotColor;
  int trackedFrames = 0;
  int onPath = 0;
  int collisions = 0;
  boolean reachedGoal = false;
  boolean wasOffPath = false; // NEW: track previous frame state
  float timeSec = 0;
  float accuracy = 0;
  String fact = "";

  TherapyStats(String label, color dotColor) {
    this.label = label;
    this.dotColor = dotColor;
  }

  void reset() {
    trackedFrames = onPath = collisions = 0;
    reachedGoal = false;
    wasOffPath = false; // reset the state flag
    timeSec = 0;
    accuracy = 0;
    fact = "";
  }

  void refreshLive(int startMillis) {
    accuracy = (trackedFrames == 0) ? 0 : (onPath / float(trackedFrames));
    timeSec = (millis() - startMillis) / 1000.0;
  }

  void finish(int startMillis, int endMillis) {
    timeSec = max(0.01, (endMillis - startMillis) / 1000.0);
    accuracy = (trackedFrames == 0) ? 0 : (onPath / float(trackedFrames));
    fact = pickTherapyFact(accuracy, timeSec);
  }
}

class ColorTracker {
  color target;
  PVector camPos = null;
  PVector smoothed = null;
  boolean found = false;
  float lastDist = Float.MAX_VALUE;
  int step = 3;
  int windowRadius = 120;
  float alpha = 0.25;
  volatile int[] latestPixels = null;
  volatile int latestW = 0;
  volatile int latestH = 0;
  volatile boolean running = false;
  Thread worker;

  ColorTracker(color c) {
    target = c;
  }

  void setColor(color c) {
    target = c;
  }

  void setFrame(int[] pixels, int w, int h) {
    latestPixels = pixels;
    latestW = w;
    latestH = h;
  }

  void startThread() {
    running = true;
    worker = new Thread(new Runnable() {
      public void run() {
        while (running) {
          if (latestPixels == null || latestW == 0 || latestH == 0) {
            delay(2);
            continue;
          }
          process(latestPixels, latestW, latestH);
          delay(1); // yield a bit
        }
      }
    });
    worker.start();
  }

  void stopThread() {
    running = false;
  }

  void process(int[] pixels, int w, int h) {
    int[] scanBox = scanBounds(w, h);

    // First pass: windowed search if we already have a position
    int minX = scanBox[0], maxX = scanBox[1], minY = scanBox[2], maxY = scanBox[3];
    boolean usedWindow = false;
    if (camPos != null) {
      minX = max(minX, int(camPos.x) - windowRadius);
      maxX = min(maxX, int(camPos.x) + windowRadius);
      minY = max(minY, int(camPos.y) - windowRadius);
      maxY = min(maxY, int(camPos.y) + windowRadius);
      usedWindow = true;
    }

    DetectionResult res = scanRegion(pixels, w, h, minX, maxX, minY, maxY);

    // Fallback to full-frame (still inside scanBox) if not good enough
    if (usedWindow && (res.bestDist > colorThreshold || res.bx == -1)) {
      res = scanRegion(pixels, w, h, scanBox[0], scanBox[1], scanBox[2], scanBox[3]);
    }

    lastDist = res.bestDist;
    boolean withinHard = (res.bx != -1 && res.bestDist <= colorThreshold);
    boolean withinSoft = (camPos != null && lastDist <= colorThreshold * colorToleranceFactor);

    if (withinHard || withinSoft) {
      if (res.bx != -1) {
        camPos = centroidAround(res.bx, res.by, pixels, w, h, res.bestDist);
      }
      float dx = map(camPos.x, scanBox[0], scanBox[1], width, 0);
      float dy = map(camPos.y, scanBox[2], scanBox[3], 0, height);
      if (smoothed == null) smoothed = new PVector(dx, dy);
      else smoothed.lerp(new PVector(dx, dy), alpha);
      found = true;
    } else {
      found = false;
    }
  }

  DetectionResult scanRegion(int[] pixels, int w, int h, int minX, int maxX, int minY, int maxY) {
    float best = Float.MAX_VALUE;
    int bx = -1, by = -1;
    for (int y = minY; y < maxY; y += step) {
      int row = y * w;
      for (int x = minX; x < maxX; x += step) {
        float d = colorDist(pixels[row + x], target);
        if (d < best) {
          best = d;
          bx = x;
          by = y;
        }
      }
    }
    return new DetectionResult(bx, by, best);
  }

  PVector centroidAround(int cx, int cy, int[] pixels, int w, int h, float bestDist) {
    float limit = min(colorThreshold * colorToleranceFactor, bestDist * 1.08);
    int radius = max(8, step * 3);
    float sumX = 0, sumY = 0, count = 0;
    int minX = max(0, cx - radius);
    int maxX = min(w, cx + radius);
    int minY = max(0, cy - radius);
    int maxY = min(h, cy + radius);
    for (int y = minY; y < maxY; y++) {
      int row = y * w;
      for (int x = minX; x < maxX; x++) {
        float d = colorDist(pixels[row + x], target);
        if (d <= limit) {
          sumX += x;
          sumY += y;
          count++;
        }
      }
    }
    if (count > 0) {
      return new PVector(sumX / count, sumY / count);
    }
    return new PVector(cx, cy);
  }

  int[] scanBounds(int w, int h) {
    // largest rect of screenAspect inside camera, scaled by scanScale
    float boxW, boxH;
    if (w / float(h) > screenAspect) {
      // camera wider than target aspect
      boxH = h;
      boxW = boxH * screenAspect;
    } else {
      boxW = w;
      boxH = boxW / screenAspect;
    }
    boxW *= scanScale;
    boxH *= scanScale;
    float offsetX = (w - boxW) / 2.0;
    float offsetY = (h - boxH) / 2.0;
    int minX = int(offsetX);
    int maxX = int(offsetX + boxW);
    int minY = int(offsetY);
    int maxY = int(offsetY + boxH);
    return new int[] {minX, maxX, minY, maxY};
  }
}

class Tank {
  PVector pos;
  float angle = 0;
  float turretAngle = 0;
  float speed = 3.2;
  float radius = 26;
  float baseRadius = 26; // NEW: starting size
  int hits = 0;
  int maxLives = 5; // NEW
  int shapeType; // NEW: 0 = square, 1 = pentagon
  color body;
  boolean isPlayer;

  Tank(PVector p, color c, boolean playerControlled, int shape) { // ADDED shape parameter
    pos = p.copy();
    body = c;
    isPlayer = playerControlled;
    shapeType = shape; // NEW
    turretAngle = random(TWO_PI);
    baseRadius = 30; // NEW
    radius = baseRadius; // NEW
  }

  void move(PVector dir, ArrayList<Obstacle> obs) {
    if (dir.magSq() > 0.001) dir.normalize();
    PVector next = PVector.add(pos, PVector.mult(dir, speed));
    if (!collides(next, obs)) {
      pos = next;
    }
  }

  boolean collides(PVector np, ArrayList<Obstacle> obs) {
    if (np.x - radius < 0 || np.x + radius > width || np.y - radius < 0 || np.y + radius > height) {
      return true;
    }
    for (Obstacle o : obs) {
      if (o.circleHits(np, radius)) return true;
    }
    return false;
  }

  // NEW METHOD
  void takeDamage() {
    hits++;
    // Shrink by 15% each hit
    float lifePercent = 1.0 - (hits / float(maxLives));
    radius = baseRadius * (0.45 + 0.55 * lifePercent);
    speed = 3.2 * (0.6 + 0.4 * lifePercent);
  }

  void draw() {
    pushMatrix();
    translate(pos.x, pos.y);
    
    // Draw glow/shadow
    noStroke();
    fill(0, 0, 0, 80);
    if (shapeType == 0) { // NEW: different shapes
      rectMode(CENTER);
      rect(0, 0, radius * 2.2, radius * 2.2);
      rectMode(CORNER);
    } else {
      polygon(0, 0, radius * 1.1, 5);
    }
    
    // Draw main shape
    fill(body);
    if (shapeType == 0) { // NEW: square
      rectMode(CENTER);
      rect(0, 0, radius * 2, radius * 2, 4);
      rectMode(CORNER);
    } else { // NEW: pentagon
      polygon(0, 0, radius, 5);
    }
    
    // Draw turret barrel
    rotate(turretAngle);
    stroke(255);
    strokeWeight(6);
    line(0, 0, radius + 10, 0);
    
    popMatrix();
    
    // Draw life indicator
    drawLives(); // NEW METHOD CALL
  }
  
  // NEW METHOD
  void drawLives() {
    int livesLeft = maxLives - hits;
    float barWidth = radius * 2;
    float barHeight = 6;
    float barX = pos.x - radius;
    float barY = pos.y - radius - 12;
    
    // Background
    noStroke();
    fill(50, 50, 50, 180);
    rect(barX, barY, barWidth, barHeight, 3);
    
    // Life bar
    float lifePercent = livesLeft / float(maxLives);
    color barColor = lerpColor(color(255, 50, 50), color(50, 255, 100), lifePercent);
    fill(barColor);
    rect(barX, barY, barWidth * lifePercent, barHeight, 3);
  }
}

class Obstacle {
  float x, y, w, h;
  
  Obstacle(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void draw() {
    rect(x, y, w, h, 8);
  }

  boolean containsPoint(float px, float py) {
    return px > x && px < x + w && py > y && py < y + h;
  }

  boolean circleHits(PVector p, float r) {
    float cx = constrain(p.x, x, x + w);
    float cy = constrain(p.y, y, y + h);
    return dist(p.x, p.y, cx, cy) < r;
  }
}

  class Bullet {
  PVector pos;
  PVector vel;
  Tank owner;
  int life = 0;
  boolean expired = false;
  int shapeType; // NEW: matches owner's shape

  Bullet(PVector p, PVector v, Tank o) {
    pos = p.copy();
    vel = v.copy();
    owner = o;
    shapeType = o.shapeType; // NEW
  }

  void update() {
    pos.add(vel);
    life++;
    if (pos.x < 0 || pos.x > width || pos.y < 0 || pos.y > height) expired = true;
    if (life > 240) expired = true;
  }

  boolean hitsTank(Tank t) {
    return pos.dist(t.pos) < t.radius;
  }
  
  // NEW METHOD
  void draw() {
    pushMatrix();
    translate(pos.x, pos.y);
    noStroke();
    fill(owner.body);
    
    float size = 12;
    if (shapeType == 0) {
      // Square bullet
      rectMode(CENTER);
      rect(0, 0, size, size);
      rectMode(CORNER);
    } else {
      // Pentagon bullet
      polygon(0, 0, size * 0.7, 5);
    }
    
    popMatrix();
  }
}

class DetectionResult {
  int bx, by;
  float bestDist;
  DetectionResult(int bx, int by, float best) {
    this.bx = bx;
    this.by = by;
    this.bestDist = best;
  }
}

// ------------------------------------------------------------
// Camera preview window (separate)
// ------------------------------------------------------------
class PreviewWindow extends PApplet {
  PImage previewImg;
  PVector posA, posB;
  boolean foundA, foundB;
  color colorA, colorB;
  boolean twoPlayers = false;

  public void settings() {
    size(320, 240);
  }

  public void setup() {
    surface.setTitle("Camera Preview");
  }

  public synchronized void setFrame(PImage f, ColorTracker a, ColorTracker b, boolean twoPlayers) {
    if (f != null) {
      previewImg = f.copy();
    }
    this.twoPlayers = twoPlayers;
    foundA = a.found;
    colorA = a.target;
    posA = (a.camPos == null) ? null : a.camPos.copy();
    foundB = b.found && twoPlayers;
    colorB = b.target;
    posB = (b.camPos == null) ? null : b.camPos.copy();
  }

  public synchronized void draw() {
    background(20);
    if (previewImg != null) {
      pushMatrix();
      translate(width, 0);
      scale(-1, 1);
      image(previewImg, 0, 0, width, height);
      popMatrix();
      drawScanBox();
      drawDot(posA, foundA, colorA);
      if (twoPlayers) drawDot(posB, foundB, colorB);
    }
    drawLegends();
  }

  void drawDot(PVector camPos, boolean found, color c) {
    if (!found || camPos == null || previewImg == null) return;
    float sx = width / float(previewImg.width);
    float sy = height / float(previewImg.height);
    float dx = (previewImg.width - camPos.x) * sx;
    float dy = camPos.y * sy;
    noStroke();
    fill(c);
    ellipse(dx, dy, 14, 14);
  }

  void drawLegends() {
    fill(0, 0, 0, 160);
    noStroke();
    rect(5, 5, width - 10, 46, 6);
    fill(255);
    textAlign(LEFT, CENTER);
    textSize(12);
    text("Primary: " + rgbString(colorA) + (foundA ? " (seen)" : " (not seen)"), 12, 18);
    if (twoPlayers) {
      text("Secondary: " + rgbString(colorB) + (foundB ? " (seen)" : " (not seen)"), 12, 34);
    } else {
      text("Secondary disabled (1P mode)", 12, 34);
    }
  }

  void drawScanBox() {
    if (previewImg == null) return;
    int[] bounds = calcScanBounds(previewImg.width, previewImg.height);
    float sx = width / float(previewImg.width);
    float sy = height / float(previewImg.height);
    float boxW = (bounds[1] - bounds[0]);
    float boxH = (bounds[3] - bounds[2]);
    float ox = bounds[0];
    float oy = bounds[2];
    pushMatrix();
    translate(width, 0);
    scale(-1, 1);
    noFill();
    stroke(255, 60, 60);
    strokeWeight(2);
    rect(ox * sx, oy * sy, boxW * sx, boxH * sy);
    popMatrix();
  }

  int[] calcScanBounds(int w, int h) {
    float boxW, boxH;
    if (w / float(h) > screenAspect) {
      boxH = h;
      boxW = boxH * screenAspect;
    } else {
      boxW = w;
      boxH = boxW / screenAspect;
    }
    boxW *= scanScale;
    boxH *= scanScale;
    float offsetX = (w - boxW) / 2.0;
    float offsetY = (h - boxH) / 2.0;
    int minX = int(offsetX);
    int maxX = int(offsetX + boxW);
    int minY = int(offsetY);
    int maxY = int(offsetY + boxH);
    return new int[] {minX, maxX, minY, maxY};
  }
}

// ------------------------------------------------------------
// Small utilities
// ------------------------------------------------------------
float colorDist(color a, color b) {
  float dr = red(a) - red(b);
  float dg = green(a) - green(b);
  float db = blue(a) - blue(b);
  return sqrt(dr * dr + dg * dg + db * db);
}

void polygon(float x, float y, float radius, int npoints) {
  float angle = TWO_PI / npoints;
  beginShape();
  for (float a = -HALF_PI; a < TWO_PI - HALF_PI; a += angle) {
    float sx = x + cos(a) * radius;
    float sy = y + sin(a) * radius;
    vertex(sx, sy);
  }
  endShape(CLOSE);
}

String rgbString(color c) {
  return int(red(c)) + "," + int(green(c)) + "," + int(blue(c));
}

void exit() {
  if (previewWin != null) {
    previewWin.dispose();
  }
  releaseControlKeys();
  releaseMouse();
  trackerA.stopThread();
  trackerB.stopThread();
  super.exit();
}
