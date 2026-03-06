#!/usr/bin/env bun
/**
 * En dev: ejecuta la app con --watch y además observa .env.
 * Si cambia .env, reinicia el proceso para recargar variables.
 */
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const APP_DIR = path.resolve(__dirname, "..");
const ENV_PATH = path.join(APP_DIR, ".env");

function loadEnvFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    const env = {};
    for (const line of content.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx === -1) continue;
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim();
      val = val.replace(/^(['"])(.*)\1$/, "$2");
      env[key] = val;
    }
    return env;
  } catch {
    return {};
  }
}

function startApp() {
  const freshEnv = { ...process.env, ...loadEnvFile(ENV_PATH), NODE_ENV: "development" };
  const childCmd = freshEnv.DEV_CHILD_CMD;
  const args = childCmd
    ? ["-c", childCmd]
    : ["--watch", "run", "index.js"];
  const bin = childCmd ? "sh" : "bun";
  const child = spawn(bin, args, {
    cwd: APP_DIR,
    stdio: "inherit",
    env: freshEnv,
  });
  child.on("exit", (code, signal) => {
    if (restarting) return;
    if (code !== null && code !== 0) process.exit(code);
  });
  return child;
}

let child = startApp();
let restarting = false;

function restartOnEnvChange() {
  try {
    fs.watch(ENV_PATH, (event, filename) => {
      if (event === "change" && filename) {
        console.log("[dev-watch] .env cambió, reiniciando app...");
        restarting = true;
        child.kill("SIGTERM");
        child = startApp();
        restarting = false;
      }
    });
  } catch (err) {
    if (err.code !== "ENOENT") console.error("[dev-watch] No se pudo observar .env:", err.message);
  }
}

if (fs.existsSync(ENV_PATH)) {
  restartOnEnvChange();
}
