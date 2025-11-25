// =============================================================
// SHAPE BLAST + CHATGPT AI BOT (Standalone Processing Sketch)
// Rudhva Patel - AI Opponent controlled by ChatGPT
// Requires internet + OpenAI API key
// =============================================================

import java.net.*;
import java.io.*;
import processing.data.*;

Tank player;
Tank bot;
ArrayList<Bullet> bullets = new ArrayList<Bullet>();

boolean keyW, keyA, keyS, keyD, keyShoot;
boolean shapeGameOver = false;
int lastPlayerShot = 0;
int lastBotShot = 0;

int playerMaxHits = 5;
int botMaxHits = 5;
String botStrategy = "idle";
int lastGPTCall = 0;

// ================= CONFIG =================

String OPENAI_API_KEY = "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";

// =========================================

void settings() {
  size(900, 600);
}

void setup() {
  surface.setTitle("Shape Blast - ChatGPT AI Bot");
  initGame();
}

void initGame() {
  bullets.clear();
  player = new Tank(new PVector(width*0.2, height*0.5), color(90,200,255), true);
  bot = new Tank(new PVector(width*0.8, height*0.5), color(255,180,90), false);
  shapeGameOver = false;
}

void draw() {
  background(20);
  drawHUD();
  updateWorld();
  drawBullets();
  player.draw();
  bot.draw();
}

// ================= GAME LOOP =================

void updateWorld() {
  if (shapeGameOver) return;
  handlePlayer();

  if (millis() - lastGPTCall > 2000) {
    botStrategy = askChatGPTForStrategy();
    lastGPTCall = millis();
  }

  handleBotAI(botStrategy);
  updateBullets();
}

void handlePlayer() {
  PVector move = new PVector();
  if (keyW) move.y -= 1;
  if (keyS) move.y += 1;
  if (keyA) move.x -= 1;
  if (keyD) move.x += 1;
  player.move(move);

  if (keyShoot && millis() - lastPlayerShot > 250) {
    shoot(player);
    lastPlayerShot = millis();
  }
}

// ================= GPT AI BEHAVIOR =================

void handleBotAI(String mode) {
  PVector toPlayer = PVector.sub(player.pos, bot.pos);
  float dist = toPlayer.mag();

  PVector moveDir = new PVector();

  if (mode.equals("attack")) moveDir = toPlayer;
  if (mode.equals("retreat")) moveDir = PVector.sub(bot.pos, player.pos);
  if (mode.equals("strafe")) moveDir = new PVector(-toPlayer.y, toPlayer.x);

  moveDir.normalize();
  bot.move(moveDir);

  float angle = atan2(toPlayer.y, toPlayer.x);
  bot.turretAngle = lerpAngle(bot.turretAngle, angle, 0.2);

  if (millis() - lastBotShot > 500 && dist < 350) {
    shoot(bot);
    lastBotShot = millis();
  }
}

// ================= GPT API =================

String askChatGPTForStrategy() {
  try {
    URL url = new URL("https://api.groq.com/openai/v1/chat/completions");

    HttpURLConnection conn = (HttpURLConnection) url.openConnection();

    conn.setRequestMethod("POST");
    conn.setRequestProperty("Content-Type", "application/json");
    conn.setRequestProperty("Authorization", "Bearer " + OPENAI_API_KEY);
    conn.setDoOutput(true);

    JSONObject msg = new JSONObject();
    msg.setString("role", "user");
    msg.setString("content",
      "Act as a game AI. Choose one word: attack, retreat, or strafe. " +
      "PlayerHits:" + player.hits + " BotHits:" + bot.hits);

    JSONArray messages = new JSONArray();
    messages.append(msg);

    JSONObject body = new JSONObject();
    body.setString("model", "gpt-4.1-mini");
    body.setJSONArray("messages", messages);

    OutputStream os = conn.getOutputStream();
    os.write(body.toString().getBytes("UTF-8"));
    os.close();

    BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream()));
    StringBuilder result = new StringBuilder();
    String line;
    while ((line = br.readLine()) != null) result.append(line);

    JSONObject response = JSONObject.parse(result.toString());
    String content = response.getJSONArray("choices")
      .getJSONObject(0)
      .getJSONObject("message")
      .getString("content");

    content = content.trim().toLowerCase();
    if (!content.equals("attack") && !content.equals("retreat") && !content.equals("strafe")) {
      return "attack";
    }
    return content;

  } catch (Exception e) {
    println(e.getMessage());
    return "attack";
  }
}

// ================= UTILITIES =================

void shoot(Tank t) {
  PVector dir = new PVector(cos(t.turretAngle), sin(t.turretAngle));
  bullets.add(new Bullet(PVector.add(t.pos, PVector.mult(dir, t.radius)), PVector.mult(dir, 6), t));
}

void updateBullets() {
  for (Bullet b : bullets) {
    b.update();
    if (!b.expired && b.owner != player && b.hits(player)) {
      player.hits++;
      b.expired = true;
    }
    if (!b.expired && b.owner != bot && b.hits(bot)) {
      bot.hits++;
      b.expired = true;
    }
  }
}

void drawBullets() {
  fill(255);
  for (Bullet b : bullets) ellipse(b.pos.x, b.pos.y, 10, 10);
}

float lerpAngle(float a, float b, float amt) {
  float diff = atan2(sin(b-a), cos(b-a));
  return a + diff * amt;
}

// ================= DRAW HUD =================

void drawHUD() {
  fill(255);
  text("Bot Strategy: " + botStrategy, 20, 20);
  text("Player Hits: " + player.hits + "/" + playerMaxHits, 20, 40);
  text("Bot Hits: " + bot.hits + "/" + botMaxHits, 20, 60);
}

// ================= INPUT =================

void keyPressed() {
  if (key == 'w') keyW = true;
  if (key == 's') keyS = true;
  if (key == 'a') keyA = true;
  if (key == 'd') keyD = true;
  if (key == ' ') keyShoot = true;
}

void keyReleased() {
  if (key == 'w') keyW = false;
  if (key == 's') keyS = false;
  if (key == 'a') keyA = false;
  if (key == 'd') keyD = false;
  if (key == ' ') keyShoot = false;
}

// ================= CLASSES =================

class Tank {
  PVector pos;
  float turretAngle = 0;
  float radius = 20;
  int hits = 0;
  color col;

  Tank(PVector p, color c, boolean isPlayer) {
    pos = p.copy();
    col = c;
  }

  void move(PVector dir) {
    if (dir.mag() > 0) dir.normalize();
    pos.add(dir.mult(3));
  }

  void draw() {
    pushMatrix();
    translate(pos.x, pos.y);
    rotate(turretAngle);
    fill(col);
    ellipse(0, 0, radius*2, radius*2);
    stroke(255);
    line(0, 0, radius+10, 0);
    popMatrix();
  }
}

class Bullet {
  PVector pos, vel;
  Tank owner;
  boolean expired = false;

  Bullet(PVector p, PVector v, Tank o) {
    pos = p.copy();
    vel = v.copy();
    owner = o;
  }

  void update() { pos.add(vel); }

  boolean hits(Tank t) {
    return pos.dist(t.pos) < t.radius;
  }
}
